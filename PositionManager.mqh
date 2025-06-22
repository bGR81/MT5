#include <Trade\Trade.mqh>
extern CTrade trade;

extern int buy_opened_this_bar;
extern int sell_opened_this_bar;
extern int max_buy_per_bar;
extern int max_sell_per_bar;
extern int max_open_buy;
extern int max_open_sell;
extern bool enable_auto_risk;
extern double start_lot_size;
extern double take_profit_pips;
extern double stop_loss_pips;

// CalculateDynamicLot() fonksiyonu RiskManager.mqh'de ise, burada prototipini belirtin:
double CalculateDynamicLot();

void InitPositionManager() {}

void ResetBarCounters()
{
    buy_opened_this_bar = 0;
    sell_opened_this_bar = 0;
}

void CloseAllPositionsOfType(int type, string reason)
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket) && (int)PositionGetInteger(POSITION_TYPE) == type)
        {
            trade.PositionClose(ticket);
            Print("Pozisyon kapatıldı | Type:", type, " | Ticket:", ticket, " | Sebep:", reason);
        }
    }
}

// Pozisyon açma fonksiyonu, sinyal timestamp'ı ile
void TryOpenPosition(string action, long tv_timestamp = 0)
{
    if (action != "BUY" && action != "SELL") return;

    int open_buy = 0, open_sell = 0;
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (PositionSelectByTicket(PositionGetTicket(i)))
        {
            if ((int)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)  open_buy++;
            if ((int)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) open_sell++;
        }
    }
    if (action == "BUY" && open_buy >= max_open_buy)  { Print("Maksimum açık BUY."); return; }
    if (action == "SELL" && open_sell >= max_open_sell) { Print("Maksimum açık SELL."); return; }

    if (action == "BUY" && buy_opened_this_bar >= max_buy_per_bar) { Print("Bu bar içinde max BUY."); return; }
    if (action == "SELL" && sell_opened_this_bar >= max_sell_per_bar) { Print("Bu bar içinde max SELL."); return; }

    double used_lot = start_lot_size;
    if (enable_auto_risk) used_lot = CalculateDynamicLot();

    double sl = 0, tp = 0;
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double price = (action == "BUY") ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    if (take_profit_pips > 0)
        tp = (action == "BUY") ? price + take_profit_pips * point : price - take_profit_pips * point;
    if (stop_loss_pips > 0)
        sl = (action == "BUY") ? price - stop_loss_pips * point : price + stop_loss_pips * point;

    string timestamp_str = (tv_timestamp > 0) ? TimeToString((datetime)tv_timestamp, TIME_DATE|TIME_SECONDS) : TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);

    bool result = false;
    if (action == "BUY")
    {
        result = trade.Buy(used_lot, Symbol(), 0, sl, tp, "TV BUY " + timestamp_str);
        if (result) { buy_opened_this_bar++; Print("BUY açıldı. Lot:", used_lot, " Zaman:", timestamp_str); }
    }
    else if (action == "SELL")
    {
        result = trade.Sell(used_lot, Symbol(), 0, sl, tp, "TV SELL " + timestamp_str);
        if (result) { sell_opened_this_bar++; Print("SELL açıldı. Lot:", used_lot, " Zaman:", timestamp_str); }
    }
}