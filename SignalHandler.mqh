#include "Martingale.mqh"
#include "PositionManager.mqh"
extern int max_open_buy;
extern int max_open_sell;

// Sadece rakam olan string'i integer'a çevirmek için kontrol
bool IsStringInteger(string s) {
   if(StringLen(s)==0) return false;
   ushort c;
   for(int i=0; i<StringLen(s); i++) {
      c = StringGetCharacter(s, i);
      if(c<48 || c>57) return false;
   }
   return true;
}

// Sinyali işle
void HandleSignal(string action, string tv_symbol, int max_open_buy_signal, int max_open_sell_signal, long tv_timestamp)
{
    if(tv_symbol != "" && tv_symbol != Symbol()) return;

    if (max_open_buy_signal > 0 && max_open_buy_signal < 100) max_open_buy = max_open_buy_signal;
    if (max_open_sell_signal > 0 && max_open_sell_signal < 100) max_open_sell = max_open_sell_signal;

    if (action == "RESET")
    {
        ResetMartingaleState();
        Print("[TV] Martingale resetlendi (RESET komutu)");
        return;
    }
    if (action == "BUY" || action == "SELL")
    {
        TryOpenPosition(action, tv_timestamp);
        return;
    }
    if (action == "CLOSE_BUY")
    {
        CloseAllPositionsOfType(POSITION_TYPE_BUY, "TV Sinyaliyle BUY kapama");
        return;
    }
    if (action == "CLOSE_SELL")
    {
        CloseAllPositionsOfType(POSITION_TYPE_SELL, "TV Sinyaliyle SELL kapama");
        return;
    }
}

// ... (GetTVSignal fonksiyonu burada devam eder)