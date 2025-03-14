import json
import pprint
import pandas as pd

with open('data.json', 'r', encoding='utf-8') as file:
    data = json.load(file)

parsed_data = []

for elem in data.get('items', []):
    try:
        for i in range(100):
            data = elem['items'][i]['productInfo']
            parsed_data.append({
                                    'Название карты': data.get('productName'),
                                    'Полное название': data.get('name'),
                                    'Банк': data.get('partner', {}).get('name'),
                                    'Процентная ставка': data.get('meta', {}).get('rateRange'),
                                    'Кредитный лимит': data.get('meta', {}).get('amountRange'),
                                    'Снятие в своих банкоматах': data.get('meta', {}).get('cashWithdrawalsAtAtms'),
                                    'Снятие в чужих банкоматах': data.get('meta', {}).get('cashWithdrawalsAtOtherBankAtms')
        })

    except IndexError:
        continue

df = pd.DataFrame(parsed_data)
df.to_excel('credit_cards.xlsx', index=False)