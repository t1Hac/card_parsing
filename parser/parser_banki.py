import requests
from bs4 import BeautifulSoup
import json

url = "https://www.banki.ru/products/creditcards/"

headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
}

response = requests.get(url, headers=headers)
soup = BeautifulSoup(response.text, 'html.parser')

data_tags = soup.find_all('div', {'data-module-options': True})
for data_tag in data_tags:
    if data_tag:
        data_json = data_tag.get('data-module-options')
        try:
            data = json.loads(data_json)
            if 'Полная стоимость кредита' in data:
                break
        except json.JSONDecodeError:
            continue

        data = data.get('offers')
        if data:
            data.get('items')
            with open('data.json', 'w', encoding='utf-8') as file:
                json.dump(data, file, ensure_ascii=False, indent=4)