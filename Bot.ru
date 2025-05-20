import os
import time
import requests
import telebot
import pandas as pd
import mplfinance as mpf
from datetime import datetime, timedelta
from io import BytesIO

# Получаем токен из переменной окружения
BOT_TOKEN = os.getenv("BOT_TOKEN")
CHAT_ID = os.getenv("CHAT_ID")  # Добавь на сервере как переменную тоже

bot = telebot.TeleBot(BOT_TOKEN)

# Топ-10 монет (можно изменить)
symbols = [
    "BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT", "XRPUSDT",
    "DOGEUSDT", "ADAUSDT", "AVAXUSDT", "MATICUSDT", "DOTUSDT"
]

# Получение данных с Binance
def get_klines(symbol, interval="1h", limit=50):
    url = f"https://api.binance.com/api/v3/klines?symbol={symbol}&interval={interval}&limit={limit}"
    r = requests.get(url)
    data = r.json()
    df = pd.DataFrame(data, columns=[
        'timestamp', 'open', 'high', 'low', 'close', 'volume',
        'close_time', 'quote_asset_volume', 'num_trades',
        'taker_buy_base_asset_volume', 'taker_buy_quote_asset_volume', 'ignore'
    ])
    df['timestamp'] = pd.to_datetime(df['timestamp'], unit='ms')
    df.set_index('timestamp', inplace=True)
    df = df.astype(float)
    return df[['open', 'high', 'low', 'close', 'volume']]

# Построение графика
def draw_chart(df, symbol):
    buf = BytesIO()
    mpf.plot(
        df[-30:], type='candle', style='charles',
        title=f"{symbol} | 1H", ylabel='Цена',
        volume=True, mav=(5,10),
        savefig=dict(fname=buf, format='png')
    )
    buf.seek(0)
    return buf

# Генерация сигнала
def analyze_symbol(symbol):
    df = get_klines(symbol)
    last = df.iloc[-1]
    trend = "вверх" if last['close'] > df['close'].mean() else "вниз"

    tp = round(last['close'] * 1.03, 2)
    sl = round(last['close'] * 0.97, 2)
    entry = round(last['close'], 2)

    reasons = []
    if trend == "вверх":
        reasons.append("• Тренд вверх")
    if last['volume'] > df['volume'].mean():
        reasons.append("• Повышенный объём")
    if last['low'] <= df['low'].rolling(10).min().iloc[-1]:
        reasons.append("• Уровень поддержки")

    if len(reasons) >= 2:
        return {
            "symbol": symbol,
            "entry": entry,
            "tp": tp,
            "sl": sl,
            "reasons": reasons,
            "df": df
        }
    return None

# Команда запуска
@bot.message_handler(commands=['signal'])
def signal_handler(message):
    for symbol in symbols:
        result = analyze_symbol(symbol)
        if result:
            now = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")
            text = f"""✅ Сигнал по {result['symbol']}
Цена входа: {result['entry']}
TP: {result['tp']}
SL: {result['sl']}

Причины сигнала:
{chr(10).join(result['reasons'])}

⏰ {now}
Проверь график ниже"""
            chart = draw_chart(result['df'], result['symbol'])
            bot.send_message(message.chat.id, text)
            bot.send_photo(message.chat.id, photo=chart)
            time.sleep(2)

# Старт
print("Бот запущен...")
bot.polling()
