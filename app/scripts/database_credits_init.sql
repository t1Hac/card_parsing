CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE categories (
    category_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL, -- Название категории (например, "путешествия", "продукты")
    status VARCHAR(50) DEFAULT 'none', -- Статус категории ('none', 'preferred', 'excluded')
    CONSTRAINT unique_mcc_bank UNIQUE (bank)
);

CREATE TABLE partners (
    partner_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_name VARCHAR(100) NOT NULL, 
    bank VARCHAR(100) NOT NULL, 
    CONSTRAINT unique_partner_bank UNIQUE (name, bank)
);

CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(50) NOT NULL,
    password_hash VARCHAR(255) NOT NULL
);

CREATE TABLE credit_cards (
    card_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_name VARCHAR(100) NOT NULL,
    bank VARCHAR(100) NOT NULL, 
    interest_rate NUMERIC(5, 2) NOT NULL, 
    credit_limit NUMERIC(15, 2) NOT NULL, 
    atm_withdrawal_own NUMERIC(15, 2) DEFAULT 0.0, 
    atm_withdrawal_other NUMERIC(15, 2) DEFAULT 0.0,
    grace_period INT, 
    annual_fee NUMERIC(15, 2) DEFAULT 0.0,
    max_cashback NUMERIC(15, 2), 
    balance_interest_rate NUMERIC(5, 2) DEFAULT 0.0, -- Процент на остаток
    threshold NUMERIC(15, 2), 
    status VARCHAR(50) DEFAULT 'active' -- Статус карты ('active', 'blocked', 'expired')
);

CREATE TABLE user_credit_cards (
    user_id UUID NOT NULL,
    card_id UUID NOT NULL,
    PRIMARY KEY (user_id, card_id), 
    CONSTRAINT fk_user_credit_cards_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_user_credit_cards_card FOREIGN KEY (card_id) 
        REFERENCES credit_cards(card_id) ON DELETE CASCADE
);

CREATE TABLE user_preferences (
    preference_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    category_id UUID,
    partner_id UUID,
    repayment_term VARCHAR(50), -- Тип вознаграждения ('Very important', 'Important', 'Not important')
    reward_type VARCHAR(50) NOT NULL, -- Вид вознаграждения ('cash', 'bonuses', 'miles')
    CONSTRAINT fk_user_preferences_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_user_preferences_category FOREIGN KEY (category_id) REFERENCES categories(category_id) ON DELETE SET NULL,
    CONSTRAINT fk_user_preferences_partner FOREIGN KEY (partner_id) REFERENCES partners(partner_id) ON DELETE SET NULL
);

CREATE TABLE cashback_rewards (
    reward_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_id UUID NOT NULL,
    reward_type VARCHAR(50) NOT NULL, -- Тип вознаграждения ('cash', 'bonuses', 'miles')
    cashback_amount NUMERIC(15, 2) DEFAULT 0.0, 
    CONSTRAINT fk_cashback_rewards_card FOREIGN KEY (card_id) REFERENCES credit_cards(card_id) ON DELETE CASCADE
);

CREATE TABLE purchases (
    purchase_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    card_id UUID NOT NULL,
    category_id UUID NOT NULL,
    amount NUMERIC(15, 2) NOT NULL, 
    benefit NUMERIC(15, 2) DEFAULT 0.0, 
    benefit_type VARCHAR(50) NOT NULL, -- Тип выгоды ('percentage', 'fixed')
    purchase_date TIMESTAMP DEFAULT NOW(),
    CONSTRAINT fk_purchases_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_purchases_card FOREIGN KEY (card_id) REFERENCES credit_cards(card_id) ON DELETE CASCADE,
    CONSTRAINT fk_purchases_category FOREIGN KEY (category_id) REFERENCES categories(category_id) ON DELETE CASCADE
);

CREATE OR REPLACE FUNCTION calculate_card_optimality(
    p_user_id UUID,
    p_category_id UUID DEFAULT NULL
)
RETURNS TABLE (
    card_id UUID,
    optimality_score NUMERIC
) AS $$
DECLARE
    max_interest_rate NUMERIC;
    max_credit_limit NUMERIC;
    max_grace_period NUMERIC;
    max_annual_fee NUMERIC;
    max_max_cashback NUMERIC;
    max_balance_interest NUMERIC;
BEGIN
    -- Получаем максимальные значения для нормализации среди карт пользователя
    SELECT 
        MAX(interest_rate),
        MAX(credit_limit),
        MAX(grace_period),
        MAX(annual_fee),
        MAX(max_cashback),
        MAX(balance_interest_rate)
    INTO
        max_interest_rate,
        max_credit_limit,
        max_grace_period,
        max_annual_fee,
        max_max_cashback,
        max_balance_interest
    FROM credit_cards
    WHERE user_id = p_user_id;

    -- Избегаем деления на ноль, устанавливая минимальное значение 1
    IF max_interest_rate IS NULL OR max_interest_rate = 0 THEN max_interest_rate := 1; END IF;
    IF max_credit_limit IS NULL OR max_credit_limit = 0 THEN max_credit_limit := 1; END IF;
    IF max_grace_period IS NULL OR max_grace_period = 0 THEN max_grace_period := 1; END IF;
    IF max_annual_fee IS NULL OR max_annual_fee = 0 THEN max_annual_fee := 1; END IF;
    IF max_max_cashback IS NULL OR max_max_cashback = 0 THEN max_max_cashback := 1; END IF;
    IF max_balance_interest IS NULL OR max_balance_interest = 0 THEN max_balance_interest := 1; END IF;

    RETURN QUERY
    SELECT 
        cc.card_id,
        (
            -- Факторы "меньше лучше"
            up.weight_interest_rate * (1 - cc.interest_rate / max_interest_rate) +
            up.weight_annual_fee * (1 - cc.annual_fee / max_annual_fee) +
            -- Факторы "больше лучше"
            up.weight_credit_limit * (cc.credit_limit / max_credit_limit) +
            up.weight_grace_period * (cc.grace_period / max_grace_period) +
            up.weight_max_cashback * (cc.max_cashback / max_max_cashback) +
            up.weight_balance_interest * (cc.balance_interest_rate / max_balance_interest) +
            -- Бинарные факторы
            up.weight_cashback_threshold * CASE WHEN cr.amount > cr.threshold THEN 1 ELSE 0 END +
            up.weight_reward_type_match * CASE WHEN up.reward_type = cr.reward_type THEN 1 ELSE 0 END +
            -- Учет категории, если указана (предполагаем, что связь с категориями есть в таблице card_categories)
            up.weight_category_match * CASE 
                WHEN p_category_id IS NOT NULL AND EXISTS (
                    SELECT 1 FROM card_categories ccat 
                    WHERE ccat.card_id = cc.card_id AND ccat.category_id = p_category_id
                ) THEN 1 
                ELSE 0 
            END
        ) AS optimality_score
    FROM credit_cards cc
    JOIN user_preferences up ON cc.user_id = up.user_id
    LEFT JOIN cashback_rewards cr ON cc.card_id = cr.card_id
    WHERE cc.user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION calculate_card_benefit(
    p_user_id UUID,
    p_category_id UUID DEFAULT NULL
)
RETURNS TABLE (
    card_id UUID,
    total_benefit NUMERIC,
    benefit_status VARCHAR(50)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.card_id,
        SUM(CASE 
            WHEN p.benefit_type = 'percentage' THEN p.amount * p.benefit / 100 
            ELSE p.benefit 
        END) AS total_benefit,
        CASE 
            WHEN p.benefit_type = 'percentage' THEN 'converted_rubles'
            ELSE 'rubles'
        END AS benefit_status
    FROM purchases p
    WHERE p.user_id = p_user_id
    AND (p_category_id IS NULL OR p.category_id = p_category_id)
    GROUP BY p.card_id, p.benefit_type
    ORDER BY total_benefit DESC;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_all_cards_with_benefit_and_optimality(
    p_user_id UUID,
    p_category_id UUID DEFAULT NULL
)
RETURNS TABLE (
    card_id UUID,
    name TEXT,
    bank TEXT,
    total_benefit NUMERIC,
    benefit_status VARCHAR(50),
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cc.card_id,
        cc.name::TEXT,
        cc.bank::TEXT,
        cb.total_benefit,
        cb.benefit_status,
    FROM credit_cards cc
    JOIN calculate_card_optimality(p_user_id, p_category_id) co ON cc.card_id = co.card_id
    JOIN calculate_card_benefit(p_user_id, p_category_id) cb ON cc.card_id = cb.card_id
    WHERE cc.user_id = p_user_id
    ORDER BY cb.total_benefit DESC;
END;
$$ LANGUAGE plpgsql;