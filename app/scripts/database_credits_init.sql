CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL
);

CREATE TABLE categories (
    category_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL, -- Название категории (например, "путешествия", "продукты")
    --mcc_code VARCHAR(4) NOT NULL, -- MCC-код (например, "5411" для продуктов)
    --bank VARCHAR(100), -- Банк, если категория специфична для банка
    status VARCHAR(50) DEFAULT 'none', -- Статус категории ('none', 'preferred', 'excluded')
    CONSTRAINT unique_mcc_bank UNIQUE (mcc_code, bank)
);

CREATE TABLE partners (
    partner_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL, -- Название компании-партнера
    bank VARCHAR(100) NOT NULL, -- Банк, с которым сотрудничает партнер
    CONSTRAINT unique_partner_bank UNIQUE (name, bank)
);

CREATE TABLE credit_cards (
    card_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL, -- Владелец карты
    name VARCHAR(100) NOT NULL, -- Название карты (например, "Tinkoff Platinum")
    full_name VARCHAR(150) NOT NULL, -- Полное название карты
    bank VARCHAR(100) NOT NULL, -- Банк
    interest_rate NUMERIC(5, 2) NOT NULL, -- Процентная ставка (например, 15.5%)
    credit_limit NUMERIC(15, 2) NOT NULL, -- Кредитный лимит
    atm_withdrawal_own NUMERIC(15, 2) DEFAULT 0.0, -- Комиссия за снятие в своих банкоматах
    atm_withdrawal_other NUMERIC(15, 2) DEFAULT 0.0, -- Комиссия за снятие в чужих банкоматах
    grace_period INT, -- Льготный период (в днях)
    annual_fee NUMERIC(15, 2) DEFAULT 0.0, -- Годовое обслуживание
    max_cashback NUMERIC(15, 2), -- Максимальный кэшбек за расчетный период
    balance_interest_rate NUMERIC(5, 2) DEFAULT 0.0, -- Процент на остаток
    status VARCHAR(50) DEFAULT 'active', -- Статус карты ('active', 'blocked', 'expired')
    CONSTRAINT fk_credit_cards_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE user_preferences (
    preference_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    category_id UUID, -- Предпочитаемая категория (может быть NULL)
    partner_id UUID, -- Предпочитаемый партнер (может быть NULL)
    repayment_term INT, -- Предпочитаемый срок погашения (в днях, может быть NULL)
    reward_type VARCHAR(50) NOT NULL, -- Вид вознаграждения ('cash', 'bonuses', 'miles')
    reward_preference VARCHAR(50) NOT NULL, -- Строгий фильтр или ранжирование ('strict', 'ranking')
    CONSTRAINT fk_user_preferences_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_user_preferences_category FOREIGN KEY (category_id) REFERENCES categories(category_id) ON DELETE SET NULL,
    CONSTRAINT fk_user_preferences_partner FOREIGN KEY (partner_id) REFERENCES partners(partner_id) ON DELETE SET NULL
);

ALTER TABLE user_preferences
ADD COLUMN IF NOT EXISTS weight_interest_rate NUMERIC(3, 2) DEFAULT 0.5, -- Вес для процентной ставки
ADD COLUMN IF NOT EXISTS weight_credit_limit NUMERIC(3, 2) DEFAULT 0.5, -- Вес для кредитного лимита
ADD COLUMN IF NOT EXISTS weight_grace_period NUMERIC(3, 2) DEFAULT 0.5, -- Вес для льготного периода
ADD COLUMN IF NOT EXISTS weight_annual_fee NUMERIC(3, 2) DEFAULT 0.5, -- Вес для годового обслуживания
ADD COLUMN IF NOT EXISTS weight_max_cashback NUMERIC(3, 2) DEFAULT 0.5, -- Вес для максимального кэшбека
ADD COLUMN IF NOT EXISTS weight_balance_interest NUMERIC(3, 2) DEFAULT 0.5, -- Вес для процента на остаток
ADD COLUMN IF NOT EXISTS weight_cashback_threshold NUMERIC(3, 2) DEFAULT 0.5, -- Вес для накопленного кэшбека
ADD COLUMN IF NOT EXISTS weight_category_match NUMERIC(3, 2) DEFAULT 0.5, -- Вес для совпадения категории
ADD COLUMN IF NOT EXISTS weight_reward_type_match NUMERIC(3, 2) DEFAULT 0.5; -- Вес для совпадения типа вознаграждения

CREATE TABLE cashback_rewards (
    reward_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_id UUID NOT NULL,
    reward_type VARCHAR(50) NOT NULL, -- Тип вознаграждения ('cash', 'bonuses', 'miles')
    amount NUMERIC(15, 2) DEFAULT 0.0, -- Накопленное количество
    threshold NUMERIC(15, 2), -- Порог для приоритизации карты (например, 5000 бонусов)
    CONSTRAINT fk_cashback_rewards_card FOREIGN KEY (card_id) REFERENCES credit_cards(card_id) ON DELETE CASCADE
);

-- нужна ли эта таблица
CREATE TABLE purchases (
    purchase_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    card_id UUID NOT NULL,
    category_id UUID NOT NULL,
    amount NUMERIC(15, 2) NOT NULL, -- Сумма покупки
    benefit NUMERIC(15, 2) DEFAULT 0.0, -- Выгода от покупки (рассчитывается)
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


CREATE OR REPLACE FUNCTION get_all_cards_sorted_by_optimality(
    p_user_id UUID,
    p_category_id UUID DEFAULT NULL
)
RETURNS TABLE (
    card_id UUID,
    name TEXT,
    bank TEXT,
    optimality_score NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cc.card_id,
        cc.name::TEXT,
        cc.bank::TEXT,
        co.optimality_score
    FROM calculate_card_optimality(p_user_id, p_category_id) co
    JOIN credit_cards cc ON co.card_id = cc.card_id
    ORDER BY co.optimality_score DESC;
END;
$$ LANGUAGE plpgsql;

