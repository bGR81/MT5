//+------------------------------------------------------------------+
//|   bgr 20 V54 (TV sinyali kuyruğa alma, manuel kapanış logu,      |
//|   OnTimer bar sonu kapanış kontrolü, input değişiklik logu)      |
//+------------------------------------------------------------------+
//|  Revizyon Notları (2025.06.12 - bGR81)                           |
//|                                                                  |
//|  - TV sinyali ile alım/satım piyasada açılamazsa kuyruğa alınır. |
//|    (enable_retry_queue, retry_queue_interval, retry_queue_max)    |
//|  - Kuyruktaki emirler belirli aralıklarla ve sınırlı sayıda      |
//|    tekrar denenir. Başarılı olursa kuyruktan çıkarılır.          |
//|  - Manuel kapanışlar otomatik olarak algılanır ve loglanır.      |
//|  - Bar sonu toplu kapanış OnTimer ile tickten bağımsızdır.       |
//|  - Tüm loglar ve bar mantığı tam uyumlu, parametre güncellemeleri|
//|    otomatik loglanır.                                            |
//|                                                                  |
//|  - (2025.06.12) Revizyon:                                        |
//|    instant_close_if_both_sides parametresi true ise, aynı anda   |
//|    hem BUY hem SELL pozisyonu açıldığı anda otomatik toplu       |
//|    kapanış yapılır (her iki yön açıkken anında kapama).          |
//|                                                                  |
//|  - (2025.06.12) Revizyon:                                        |
//|    CLOSE_BUY, CLOSE_SELL ve RESET sinyalleri işlevi eklendi.     |
//|    (Sinyal ile ilgili pozisyonlar veya lot/reset işlemi yapılır) |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

// --- INPUTS ---
input string webhook_url             = "https://webhook-traderx.ngrok.io/getsignal";
input double start_lot_size          = 0.01;
input bool automatic_start_lot_size = false;  // Otomatik başlangıç lotu aktif/pasif
input double equity_reference_value = 300.0;  // Referans equity (USD)
input double lot_multiplier          = 2.0;
input int    max_retries             = 2;
input double take_profit_pips        = 50;
input double stop_loss_pips          = 30;
input int    timeout                 = 5000;
input ENUM_TIMEFRAMES bar_period     = PERIOD_M5;
input int    max_open_buy            = 3;
input int    max_open_sell           = 3;
input double profit_threshold_percent = 0.10;

input bool   instant_close_if_both_sides = true;
input bool   bar_close_all_before_end_enabled = true;
input int    bar_close_all_before_end_seconds = 5;

// --- TV sinyali kuyruğu parametreleri ---
input bool   enable_retry_queue   = false;   // TV sinyali kuyruğa al/tekrar dene
input int    retry_queue_interval = 120;     // Deneme aralığı (saniye)
input int    retry_queue_max      = 5;       // Maks. tekrar denemesi

// --- Parametre Güncelleme Logları için önceki değerler:
double prev_start_lot_size          = 0.01;
double prev_lot_multiplier          = 2.0;
int    prev_max_retries             = 2;
double prev_take_profit_pips        = 50;
double prev_stop_loss_pips          = 30;
int    prev_timeout                 = 5000;
ENUM_TIMEFRAMES prev_bar_period     = PERIOD_M5;
int    prev_max_open_buy            = 3;
int    prev_max_open_sell           = 3;
double prev_profit_threshold_percent = 0.10;
bool   prev_instant_close_if_both_sides = true;
bool   prev_bar_close_all_before_end_enabled = true;
int    prev_bar_close_all_before_end_seconds = 5;
string prev_webhook_url = "";
bool   prev_enable_retry_queue   = false;
int    prev_retry_queue_interval = 120;
int    prev_retry_queue_max      = 5;

// --- Tüm state değişkenleri
double lot_for_this_bar;
int retry_for_this_bar = 0;
datetime last_bar_time = 0;
string handled_signals[];
bool bar_icerisinde_artis_yapildi = false;
bool reset_bekle_flag = false;
bool reset_flag_bar_sonunda_kapat = false;

// --- Manuel kapanış izleme için açık pozisyon takibi
ulong last_known_tickets[];
int last_known_types[];
double last_known_volumes[];

// --- Sinyal kuyruğu struct
struct RetrySignal
  {
   string            action;
   string            symbol;
   double            lot;
   int               trials;
   datetime          last_try;
  };
RetrySignal retry_queue[];

// --- Sinyal struct
struct SignalInfo
  {
   string            signal_id;
   string            action;
   string            symbol;
   int               delay_sec;
   string            raw_json;
  };

struct ClosedTrade
  {
   ulong             ticket;
   int               type;    // POSITION_TYPE_BUY or POSITION_TYPE_SELL
   double            profit;
   double            profit_percent;
   double            volume;
   datetime          close_time;
   string            reason;
  };
ClosedTrade bar_closed_trades[];
int bar_closed_count = 0;

//+------------------------------------------------------------------+
//| INPUT parametreleri değişiklik logu                              |
//+------------------------------------------------------------------+
void LogInputUpdates()
  {
   bool any_change = false;
   string log = "";

   if(start_lot_size != prev_start_lot_size)
     {
      log += StringFormat("📢 start_lot_size: %.4f → %.4f\n", prev_start_lot_size, start_lot_size);
      prev_start_lot_size = start_lot_size;
      any_change=true;
   if(lot_multiplier != prev_lot_multiplier)
     {
      log += StringFormat("📢 lot_multiplier: %.2f → %.2f\n", prev_lot_multiplier, lot_multiplier);
      prev_lot_multiplier = lot_multiplier;
      any_change=true;
   if(max_retries != prev_max_retries)
     {
      log += StringFormat("📢 max_retries: %d → %d\n", prev_max_retries, max_retries);
      prev_max_retries = max_retries;
      any_change=true;
   if(take_profit_pips != prev_take_profit_pips)
     {
      log += StringFormat("📢 take_profit_pips: %.2f → %.2f\n", prev_take_profit_pips, take_profit_pips);
      prev_take_profit_pips = take_profit_pips;
      any_change=true;
   if(stop_loss_pips != prev_stop_loss_pips)
     {
      log += StringFormat("📢 stop_loss_pips: %.2f → %.2f\n", prev_stop_loss_pips, stop_loss_pips);
      prev_stop_loss_pips = stop_loss_pips;
      any_change=true;
   if(timeout != prev_timeout)
     {
      log += StringFormat("📢 timeout: %d → %d\n", prev_timeout, timeout);
      prev_timeout = timeout;
      any_change=true;
     }
   if(bar_period != prev_bar_period)
     {
      log += StringFormat("📢 bar_period: %d → %d\n", prev_bar_period, bar_period);
      prev_bar_period = bar_period;
      any_change=true;
     }
   if(max_open_buy != prev_max_open_buy)
     {
      log += StringFormat("📢 max_open_buy: %d → %d\n", prev_max_open_buy, max_open_buy);
      prev_max_open_buy = max_open_buy;
      any_change=true;
     }
   if(max_open_sell != prev_max_open_sell)
     {
      log += StringFormat("📢 max_open_sell: %d → %d\n", prev_max_open_sell, max_open_sell);
      prev_max_open_sell = max_open_sell;
      any_change=true;
     }
   if(profit_threshold_percent != prev_profit_threshold_percent)
     {
      log += StringFormat("📢 profit_threshold_percent: %.2f → %.2f\n", prev_profit_threshold_percent, profit_threshold_percent);
      prev_profit_threshold_percent = profit_threshold_percent;
      any_change=true;
     }
      if(bar_close_all_before_end_enabled != prev_bar_close_all_before_end_enabled)
     {
      log += StringFormat("📢 bar_close_all_before_end_enabled: %s → %s\n", prev_bar_close_all_before_end_enabled?"true":"false", bar_close_all_before_end_enabled?"true":"false");
      prev_bar_close_all_before_end_enabled = bar_close_all_before_end_enabled;
      any_change=true;
     }
   if(bar_close_all_before_end_seconds != prev_bar_close_all_before_end_seconds)
     {
      log += StringFormat("📢 bar_close_all_before_end_seconds: %d → %d\n", prev_bar_close_all_before_end_seconds, bar_close_all_before_end_seconds);
      prev_bar_close_all_before_end_seconds = bar_close_all_before_end_seconds;
      any_change=true;
     }
   if(webhook_url != prev_webhook_url)
     {
      log += StringFormat("📢 webhook_url: %s → %s\n", prev_webhook_url, webhook_url);
      prev_webhook_url = webhook_url;
      any_change=true;
     }
   if(enable_retry_queue != prev_enable_retry_queue)
     {
      log += StringFormat("📢 enable_retry_queue: %s → %s\n", prev_enable_retry_queue?"true":"false", enable_retry_queue?"true":"false");
      prev_enable_retry_queue = enable_retry_queue;
      any_change=true;
     }
   if(retry_queue_interval != prev_retry_queue_interval)
     {
      log += StringFormat("📢 retry_queue_interval: %d → %d\n", prev_retry_queue_interval, retry_queue_interval);
      prev_retry_queue_interval = retry_queue_interval;
      any_change=true;
     }
   if(retry_queue_max != prev_retry_queue_max)
     {
      log += StringFormat("📢 retry_queue_max: %d → %d\n", prev_retry_queue_max, retry_queue_max);
      prev_retry_queue_max = retry_queue_max;
      any_change=true;
     }

   if(any_change)
     {
      Print("=== INPUT PARAMETRELERİ GÜNCELLENDİ ===\n" + log + "Artık yeni değerler geçerli.");
     }
  }

//+------------------------------------------------------------------+
//| Normalize lot                                                    |
//+------------------------------------------------------------------+
double NormalizeLot(double lot, double min_lot, double lot_step)
  {
   lot = MathMax(lot, min_lot);
   int digits = (int)MathCeil(-MathLog10(lot_step));
   lot = MathRound(lot / lot_step) * lot_step;
   lot = NormalizeDouble(lot, digits);
   if(lot < min_lot)
      lot = min_lot;
   return lot;
  }

//+------------------------------------------------------------------+
//| Kuyruğa ekle                                                     |
//+------------------------------------------------------------------+
void AddToRetryQueue(string action, string symbol, double lot)
  {
   if(!enable_retry_queue)
      return;
   int n = ArraySize(retry_queue);
   ArrayResize(retry_queue, n+1);
   retry_queue[n].action = action;
   retry_queue[n].symbol = symbol;
   retry_queue[n].lot = lot;
   retry_queue[n].trials = 0;
   retry_queue[n].last_try = TimeCurrent();
   Print(StringFormat("🕒 Emir kuyruğa alındı: %s %s (lot=%.4f).", action, symbol, lot));
  }
//+------------------------------------------------------------------+
//| Kuyruğu işle                                                     |
//+------------------------------------------------------------------+
void ProcessRetryQueue()
  {
   if(!enable_retry_queue)
      return;
   for(int i=ArraySize(retry_queue)-1; i>=0; i--)
     {
      if(retry_queue[i].trials >= retry_queue_max)
        {
         Print("❌ Kuyrukta maksimum deneme sayısına ulaşıldı, kaldırılıyor: ", retry_queue[i].symbol);
         ArrayRemove(retry_queue, i);
         continue;
        }
      if(TimeCurrent() - retry_queue[i].last_try >= retry_queue_interval)
        {
         bool success = TryOpenOrder(retry_queue[i].action, retry_queue[i].symbol, retry_queue[i].lot);
         retry_queue[i].last_try = TimeCurrent();
         retry_queue[i].trials++;
         if(success)
           {
            Print("✅ Kuyruktan başarılı şekilde açıldı: ", retry_queue[i].symbol);
            ArrayRemove(retry_queue, i);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Kuyruk için emir açmayı dener                                    |
//+------------------------------------------------------------------+
bool TryOpenOrder(string action, string symbol, double lot)
  {
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double used_lot = NormalizeLot(lot, min_lot, lot_step);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double stop_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double tp_points = take_profit_pips * point;
   double sl_points = stop_loss_pips * point;
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double tp = 0.0, sl = 0.0;
   int err = 0;

   if(action == "BUY")
     {
      if(CountOpenPositions(symbol, POSITION_TYPE_BUY) < max_open_buy)
        {
         if(take_profit_pips > 0)
           {
            tp = ask + tp_points;
            if(tp - ask < stop_level)
               tp = 0.0;
           }
         if(stop_loss_pips > 0)
           {
            sl = ask - sl_points;
            if(ask - sl < stop_level)
               sl = 0.0;
           }
         if(trade.Buy(used_lot, symbol, 0.0, sl, tp, "BUY"))
            return true;
         else
           {
            err = GetLastError();
            if(err==132 || err==133)
               Print("❌ [Kuyruk] Piyasa kapalı/alım başarısız: ", err);
            else
               Print("❌ [Kuyruk] Alım başarısız: ", err);
            return false;
           }
        }
     }
   else
      if(action == "SELL")
        {
         if(CountOpenPositions(symbol, POSITION_TYPE_SELL) < max_open_sell)
           {
            if(take_profit_pips > 0)
              {
               tp = bid - tp_points;
               if(bid - tp < stop_level)
                  tp = 0.0;
              }
            if(stop_loss_pips > 0)
              {
               sl = bid + sl_points;
               if(sl - bid < stop_level)
                  sl = 0.0;
              }
            if(trade.Sell(used_lot, symbol, 0.0, sl, tp, "SELL"))
               return true;
            else
              {
               err = GetLastError();
               if(err==132 || err==133)
                  Print("❌ [Kuyruk] Piyasa kapalı/satım başarısız: ", err);
               else
                  Print("❌ [Kuyruk] Satım başarısız: ", err);
               return false;
              }
           }
        }
   return false;
  }

//+------------------------------------------------------------------+
//| Her iki yön açıkken instant kapama fonksiyonu                    |
//+------------------------------------------------------------------+
void CloseInstantIfBothSides(string symbol)
  {
   if(!instant_close_if_both_sides)
      return;
   int buy_count = CountOpenPositions(symbol, POSITION_TYPE_BUY);
   int sell_count = CountOpenPositions(symbol, POSITION_TYPE_SELL);
   if(buy_count > 0 && sell_count > 0)
     {
      Print("⚡ Her iki yön açık, instant_close_if_both_sides aktif! Tüm pozisyonlar kapatılıyor.");
      CloseAllPositions(symbol, "Her iki yön açıkken otomatik kapanış");
     }
  }

//+------------------------------------------------------------------+
//| Belirli tipteki tüm pozisyonları kapatır (YENİ)                 |
//+------------------------------------------------------------------+
void CloseAllPositionsOfType(string symbol, int type, string reason)
  {
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == symbol && (int)PositionGetInteger(POSITION_TYPE) == type)
        {
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(!IsTradeAlreadyClosed(ticket))
            RecordClosedTrade(ticket, type, profit, reason);
         trade.PositionClose(ticket);
        }
     }
  }

//+------------------------------------------------------------------+
//| Bar başında state sıfırlama                                      |
//+------------------------------------------------------------------+
void ResetBarMartingaleState()
  {
   bar_closed_count = 0;
   ArrayResize(bar_closed_trades, 0);
   bar_icerisinde_artis_yapildi = false;
  }

//+------------------------------------------------------------------+
//| Detaylı kapanış log'u                                            |
//+------------------------------------------------------------------+
void LogClosedTrade(int type, double profit, double profit_percent, double volume, datetime close_time, string reason)
  {
   string typetxt = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
   string profit_str = StringFormat("%.2f%%", profit_percent);
   string profit_usd_str = StringFormat("%.2f", profit);
   string volume_str = DoubleToString(volume, 2);
   string time_str = TimeToString(close_time, TIME_DATE | TIME_SECONDS);
   Print(StringFormat("➡️ %s kapanışı: Profit(%%)=%s  Profit(USD): %s  Time: %s  Volume: %s  [Sebep: %s]",
                      typetxt, profit_str, profit_usd_str, time_str, volume_str, reason));
  }

//+------------------------------------------------------------------+
//| Bar açılışında martingale mantığı                                |
//+------------------------------------------------------------------+
void MartingaleBarCloseLogic()
  {
   if(bar_closed_count == 0)
      return;

   Print("--- Önceki bar kapanan işlemleri ---");

   int types[100];
   double profits[100];
   double profits_percent[100];
   double volumes[100];
   datetime close_times[100];
   string reasons[100];
   int count = 0;

   for(int i=0; i<bar_closed_count; i++)
     {
      LogClosedTrade(bar_closed_trades[i].type, bar_closed_trades[i].profit, bar_closed_trades[i].profit_percent, bar_closed_trades[i].volume, bar_closed_trades[i].close_time, bar_closed_trades[i].reason);
      types[count] = bar_closed_trades[i].type == POSITION_TYPE_BUY ? 0 : 1;
      profits[count] = bar_closed_trades[i].profit;
      profits_percent[count] = bar_closed_trades[i].profit_percent;
      volumes[count] = bar_closed_trades[i].volume;
      close_times[count] = bar_closed_trades[i].close_time;
      reasons[count] = bar_closed_trades[i].reason;
      count++;
     }

   int buy_indices[100], sell_indices[100];
   int buy_count = 0, sell_count = 0;
   for(int i=0; i<count; i++)
     {
      if(types[i]==0)
         buy_indices[buy_count++] = i;
      else
         sell_indices[sell_count++] = i;
     }

   int pairs = MathMin(buy_count, sell_count);
   for(int i=0; i<pairs; i++)
     {
      lot_for_this_bar = NormalizeLot(start_lot_size, SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP));
      retry_for_this_bar = 0;
      bar_icerisinde_artis_yapildi = false;
      // // // Print("📢 Bar içinde BUY & SELL çifti kapandı, lot reset!"); // iptal edildi // iptal edildi // kaldırıldı
     }

   if(reset_bekle_flag)
      return;

   bool tek_buy = (buy_count > sell_count);
   bool tek_sell = (sell_count > buy_count);

   if(tek_buy && (buy_count-sell_count > 0))
     {
      int idx = buy_indices[pairs];
      if(profits_percent[idx] < profit_threshold_percent)
        {
         if(profits_percent[idx] < 0)
           {
            if(retry_for_this_bar < max_retries && !bar_icerisinde_artis_yapildi)
              {
               retry_for_this_bar++;
               lot_for_this_bar = NormalizeLot(start_lot_size * MathPow(lot_multiplier, retry_for_this_bar), SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP));
               bar_icerisinde_artis_yapildi = true;
               Print(StringFormat("🟢 %d/%d. artış (tek kalan düşük kar/zararda BUY kapanış): lot %.4f", retry_for_this_bar, max_retries, lot_for_this_bar));
               if(retry_for_this_bar == max_retries)
                 {
                  reset_bekle_flag = true;
                 }
              }
           }
         else
           {
            Print("Tek yönlü ve kar eşiği altında fakat zararsız işlem mevcut. Artış yapılmadı.");
           }
        }
      else
        {
         Print("Tek yönlü ve kar eşiği üzerinde işlem mevcut. Artış yapılmadı.");
        }
     }
   else
      if(tek_sell && (sell_count-buy_count > 0))
        {
         int idx = sell_indices[pairs];
         if(profits_percent[idx] < profit_threshold_percent)
           {
            if(profits_percent[idx] < 0)
              {
               if(retry_for_this_bar < max_retries && !bar_icerisinde_artis_yapildi)
                 {
                  retry_for_this_bar++;
                  lot_for_this_bar = NormalizeLot(start_lot_size * MathPow(lot_multiplier, retry_for_this_bar), SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP));
                  bar_icerisinde_artis_yapildi = true;
                  Print(StringFormat("🟢 %d/%d. artış (tek kalan düşük kar/zararda SELL kapanış): lot %.4f", retry_for_this_bar, max_retries, lot_for_this_bar));
                  if(retry_for_this_bar == max_retries)
                    {
                     reset_bekle_flag = true;
                    }
                 }
              }
            else
              {
               Print("Tek yönlü ve kar eşiği altında fakat zararsız işlem mevcut. Artış yapılmadı.");
              }
           }
         else
           {
            Print("Tek yönlü ve kar eşiği üzerinde işlem mevcut. Artış yapılmadı.");
           }
        }
  }
//+------------------------------------------------------------------+
//| Pozisyon kar % hesapla                                           |
//+------------------------------------------------------------------+
double CalculateProfitPercent(int type, double profit)
  {
   double margin = 1000.0;
   if(margin == 0)
      margin = 1;
   return 100.0 * profit / margin;
  }

//+------------------------------------------------------------------+
//| Pozisyon sayısı                                                  |
//+------------------------------------------------------------------+
int CountOpenPositions(string symbol, int type)
  {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL) == symbol && (int)PositionGetInteger(POSITION_TYPE) == type)
            count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Bar sonu toplu kapanış                                           |
//+------------------------------------------------------------------+
void CloseAllPositionsBeforeBarEnd(string symbol)
  {
   if(!bar_close_all_before_end_enabled)
      return;
   datetime bar_start = iTime(symbol, bar_period, 0);
   int bar_seconds = (int)PeriodSeconds(bar_period);
   int time_passed = (int)(TimeCurrent() - bar_start);
   int time_left = bar_seconds - time_passed;
   if(time_left <= bar_close_all_before_end_seconds && time_left > 0)
     {
      int pos_count = 0;
      for(int i = 0; i < PositionsTotal(); i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == symbol)
            pos_count++;
        }
      if(pos_count > 0)
        {
         Print(StringFormat("⏰ Bar bitimine %d sn kala tüm pozisyonlar kapatılıyor.", time_left));
         CloseAllPositions(symbol, "Bar sonu toplu kapanış");
        }
     }
  }

//+------------------------------------------------------------------+
//| Tüm pozisyonları kapat (BUY/SELL)                                |
//+------------------------------------------------------------------+
void CloseAllPositions(string symbol, string reason)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == symbol)
        {
         int type = (int)PositionGetInteger(POSITION_TYPE);
         double profit = PositionGetDouble(POSITION_PROFIT);
         // Kapanış kaydından önce tekrar kontrolü:
         if(!IsTradeAlreadyClosed(ticket))
            RecordClosedTrade(ticket, type, profit, reason);
         trade.PositionClose(ticket);
        }
     }
  }

//+------------------------------------------------------------------+
//| Kapanan işlemin zaten kaydedilip kaydedilmediğini kontrol et     |
//+------------------------------------------------------------------+
bool IsTradeAlreadyClosed(ulong ticket)
  {
   for(int i=0; i<ArraySize(bar_closed_trades); i++)
      if(bar_closed_trades[i].ticket == ticket)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Her pozisyon kapandığında çağrılır                               |
//+------------------------------------------------------------------+
void RecordClosedTrade(ulong ticket, int type, double profit, string reason)
  {
// Aynı ticket daha önce kaydedildiyse tekrar kaydetme!
   if(IsTradeAlreadyClosed(ticket))
      return;

   double percent = CalculateProfitPercent(type, profit);
   double volume = 0;
   datetime close_time = TimeCurrent();
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong t = PositionGetTicket(i);
      if(t == ticket && PositionSelectByTicket(ticket))
        {
         volume = PositionGetDouble(POSITION_VOLUME);
         close_time = (datetime)PositionGetInteger(POSITION_TIME_UPDATE);
         break;
        }
     }
   int n = bar_closed_count;
   ArrayResize(bar_closed_trades, n+1);
   bar_closed_trades[n].ticket = ticket;
   bar_closed_trades[n].type = type;
   bar_closed_trades[n].profit = profit;
   bar_closed_trades[n].profit_percent = percent;
   bar_closed_trades[n].volume = volume;
   bar_closed_trades[n].close_time = close_time;
   bar_closed_trades[n].reason = reason;
   bar_closed_count++;
   LogClosedTrade(type, profit, percent, volume, close_time, reason);
   EvaluateMartingaleAfterClosure(profit, percent);
  }

//+------------------------------------------------------------------+
//| Manuel kapanışları algıla ve logla                               |
//+------------------------------------------------------------------+
void TrackAndLogManualClosures()
  {
   int total = PositionsTotal();
   ulong new_tickets[];
   int new_types[];
   double new_volumes[];
   ArrayResize(new_tickets, total);
   ArrayResize(new_types, total);
   ArrayResize(new_volumes, total);

   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         new_tickets[i] = ticket;
         new_types[i] = (int)PositionGetInteger(POSITION_TYPE);
         new_volumes[i] = PositionGetDouble(POSITION_VOLUME);
        }
     }

   for(int j = 0; j < ArraySize(last_known_tickets); j++)
     {
      ulong old_ticket = last_known_tickets[j];
      bool found = false;
      for(int i = 0; i < total; i++)
        {
         if(new_tickets[i] == old_ticket)
           {
            found = true;
            break;
           }
        }
      // Sadece daha önce bar_closed_trades'e eklenmemişse logla!
      if(!found && !IsTradeAlreadyClosed(old_ticket))
        {
         int type = last_known_types[j];
         double volume = last_known_volumes[j];
         double profit = 0;
         datetime close_time = TimeCurrent();
         if(HistorySelect(0, TimeCurrent()))
           {
            for(int h=HistoryDealsTotal()-1; h>=0; h--)
              {
               ulong deal = HistoryDealGetTicket(h);
               ulong posid = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
               if(posid == old_ticket)
                 {
                  profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
                  close_time = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
                  break;
                 }
              }
           }
         RecordClosedTrade(old_ticket, type, profit, "Manuel kapanış");
        }
     }
   ArrayResize(last_known_tickets, total);
   ArrayResize(last_known_types, total);
   ArrayResize(last_known_volumes, total);
   for(int i = 0; i < total; i++)
     {
      last_known_tickets[i] = new_tickets[i];
      last_known_types[i] = new_types[i];
      last_known_volumes[i] = new_volumes[i];
     }
  }
//+------------------------------------------------------------------+
//| Belirli bir lot ile açılış - TV sinyali kuyruğa alınır           |
//+------------------------------------------------------------------+
void ProcessSignalWithFixedLot(string action, string symbol, double lot)
  {
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double used_lot = NormalizeLot(lot, min_lot, lot_step);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double stop_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double tp_points = take_profit_pips * point;
   double sl_points = stop_loss_pips * point;
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double tp = 0.0, sl = 0.0;
   int err = 0;

// --- YENİ: Sinyal ile KAPATMA ve RESET işlemleri ---
   if(action == "CLOSE_BUY")
     {
      CloseAllPositionsOfType(symbol, POSITION_TYPE_BUY, "Sinyal ile BUY kapama");
      return;
     }
   if(action == "CLOSE_SELL")
     {
      CloseAllPositionsOfType(symbol, POSITION_TYPE_SELL, "Sinyal ile SELL kapama");
      return;
     }
   if(action == "RESET")
     {
      lot_for_this_bar = NormalizeLot(start_lot_size, min_lot, lot_step);
      retry_for_this_bar = 0;
      bar_icerisinde_artis_yapildi = false;
      Print("🔄 RESET sinyali ile lot ve retry resetlendi.");
      return;
     }

// --- Alış/Satış işlemleri ---
   if(action == "BUY")
     {
      if(CountOpenPositions(symbol, POSITION_TYPE_BUY) < max_open_buy)
        {
         if(take_profit_pips > 0)
           {
            tp = ask + tp_points;
            if(tp - ask < stop_level)
               tp = 0.0;
           }
         if(stop_loss_pips > 0)
           {
            sl = ask - sl_points;
            if(ask - sl < stop_level)
               sl = 0.0;
           }
         if(trade.Buy(used_lot, symbol, 0.0, sl, tp, "BUY"))
            Print("✅ ", symbol, " ALIM emri gönderildi!");
         else
           {
            err = GetLastError();
            if((err==132 || err==133) && enable_retry_queue)
              {
               Print("❌ Piyasa kapalı/alım başarısız, KUYRUKTA tekrar denenecek: ", err);
               AddToRetryQueue(action, symbol, lot);
              }
            else
               Print("❌ Alım emri başarısız: ", err);
           }
        }
      else
         Print("🚫 Maksimum BUY açıldı.");
     }
   else
      if(action == "SELL")
        {
         if(CountOpenPositions(symbol, POSITION_TYPE_SELL) < max_open_sell)
           {
            if(take_profit_pips > 0)
              {
               tp = bid - tp_points;
               if(bid - tp < stop_level)
                  tp = 0.0;
              }
            if(stop_loss_pips > 0)
              {
               sl = bid + sl_points;
               if(sl - bid < stop_level)
                  sl = 0.0;
              }
            if(trade.Sell(used_lot, symbol, 0.0, sl, tp, "SELL"))
               Print("✅ ", symbol, " SATIM emri gönderildi!");
            else
              {
               err = GetLastError();
               if((err==132 || err==133) && enable_retry_queue)
                 {
                  Print("❌ Piyasa kapalı/satım başarısız, KUYRUKTA tekrar denenecek: ", err);
                  AddToRetryQueue(action, symbol, lot);
                 }
               else
                  Print("❌ Satım emri başarısız: ", err);
              }
           }
         else
            Print("🚫 Maksimum SELL açıldı.");
        }

   CloseInstantIfBothSides(symbol);
  }

//+------------------------------------------------------------------+
//| TV Sinyali işleme: delay yoksa doğrudan uygula                   |
//+------------------------------------------------------------------+
void ProcessSignalNoDelay(string action, string symbol)
  {
   ProcessSignalWithFixedLot(action, symbol, lot_for_this_bar);
  }

//+------------------------------------------------------------------+
//| Kapanan işlemin ardından martingale kontrolü                     |
//+------------------------------------------------------------------+
void EvaluateMartingaleAfterClosure(double profit, double profit_percent)
  {
   if(profit_percent >= profit_threshold_percent)
     {
      // retry_for_this_bar = 0;
//      lot_for_this_bar = NormalizeLot(CalculateDynamicStartLot(), SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP));
      Print("✅ Kar eşik üzerinde. Lot reset: ", lot_for_this_bar);
     }
   else
     {
      retry_for_this_bar++;
      if(retry_for_this_bar > max_retries)
        {
         Print("🔁 Max retries aşıldı, reset ve yeniden başlatılıyor.");
         retry_for_this_bar = 0;
         lot_for_this_bar = NormalizeLot(CalculateDynamicStartLot(), SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP));
        }
      else
        {
         lot_for_this_bar = NormalizeLot(lot_for_this_bar * lot_multiplier, SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP));
         Print(StringFormat("📉 Martingale artışı: Retry=%d, Lot=%.4f", retry_for_this_bar, lot_for_this_bar));
        }
     }
  }



//+------------------------------------------------------------------+
//| Bar açılışını sadece zaman takibi için kontrol eder              |
//+------------------------------------------------------------------+
  }



//+------------------------------------------------------------------+
//| Dinamik başlangıç lotunu equity oranına göre hesaplar           |
//+------------------------------------------------------------------+

double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity_reference_value <= 0.0)
     {
      Print("⚠️ Referans equity sıfır veya geçersiz! Otomatik lot hesaplanamaz, default lot kullanılacak.");
      return start_lot_size;
     }

   double ratio = current_equity / equity_reference_value;
   double calculated_lot = NormalizeDouble(start_lot_size * ratio, 2);

   Print(StringFormat(
      "🧮 Otomatik lot hesaplama: (equity %.2f / referans %.2f) = oran %.4f → lot: %.4f",
      current_equity, equity_reference_value, ratio, calculated_lot
   ));

   return calculated_lot;



//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   LogInputUpdates();
   TrackAndLogManualClosures();
   datetime current_bar = iTime(Symbol(), bar_period, 0);

   if(current_bar != last_bar_time && last_bar_time != 0)
     {
      if(reset_bekle_flag)
        {
         lot_for_this_bar = NormalizeLot(start_lot_size, SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP));
         retry_for_this_bar = 0;
         bar_icerisinde_artis_yapildi = false;
         Print("🔄 Max retry sonrası lot reset ve yeni seri başlatıldı. bar açılış bildirimi");
         reset_flag_bar_sonunda_kapat = true;
        }
      else
        {
         MartingaleBarCloseLogic();
        }
      ResetBarMartingaleState();
      last_bar_time = current_bar;
      Print(StringFormat("🔁 Yeni bar başladı. Bu bar için lot=%.4f, retry=%d", lot_for_this_bar, retry_for_this_bar));
      if(reset_flag_bar_sonunda_kapat)
        {
         reset_bekle_flag = false;
         reset_flag_bar_sonunda_kapat = false;
         Print("🟢 Reset flag bar sonunda kapatıldı. Martingale bir sonraki bar için tekrar aktif.");
        }
     }
   if(last_bar_time == 0)
     {
      lot_for_this_bar = NormalizeLot(start_lot_size, SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP));
      retry_for_this_bar = 0;
      last_bar_time = current_bar;
      ResetBarMartingaleState();
      Print(StringFormat("🔁 İlk bar başlatıldı. Lot=%.4f, retry=%d", lot_for_this_bar, retry_for_this_bar));
     }

   char data[], result[];
   string headers = "", result_headers;
   int res = WebRequest("GET", webhook_url, headers, timeout, data, result, result_headers);
   if(res != 200)
     {
      Print("❌ WebRequest hata, kod: ", res);
      return;
     }

   string json = CharArrayToString(result);
   StringTrimLeft(json);
   StringTrimRight(json);

   if(StringLen(json) <= 2 || json == "[]")
      return;

   Print("📢 Gelen Sinyaller: ", json);

   SignalInfo close_signals[];
   SignalInfo open_signals[];

   int pos = 0;
   while((pos = StringFind(json, "{\"action\":", pos)) != -1)
     {
      int end = StringFind(json, "}", pos);
      string item = StringSubstr(json, pos, end - pos + 1);

      string signal_id = "", action = "", symbol = "";
      int delay_sec = 0;

      int id_pos = StringFind(item, "\"timestamp\":\"");
      if(id_pos >= 0)
        {
         int start = id_pos + StringLen("\"timestamp\":\"");
         int end_id = StringFind(item, "\"", start);
         signal_id = StringSubstr(item, start, end_id - start);
        }

      int action_pos = StringFind(item, "\"action\":\"");
      if(action_pos >= 0)
        {
         int start = action_pos + StringLen("\"action\":\"");
         int end_action = StringFind(item, "\"", start);
         action = StringSubstr(item, start, end_action - start);
        }

      int symbol_pos = StringFind(item, "\"symbol\":\"");
      if(symbol_pos >= 0)
        {
         int start = symbol_pos + StringLen("\"symbol\":\"");
         int end_symbol = StringFind(item, "\"", start);
         symbol = StringSubstr(item, start, end_symbol - start);
        }

      int delay_pos = StringFind(item, "\"delay\":");
      if(delay_pos >= 0)
        {
         int start = delay_pos + StringLen("\"delay\":");
         int end_delay = StringFind(item, ",", start);
         if(end_delay == -1)
            end_delay = StringFind(item, "}", start);
         string delay_str = StringSubstr(item, start, end_delay - start);
         delay_sec = StringToInteger(delay_str);
        }

      bool already_handled = false;
      for(int i = 0; i < ArraySize(handled_signals); i++)
        {
         if(handled_signals[i] == signal_id)
           {
            already_handled = true;
            break;
           }
        }

      if(!already_handled && signal_id != "" && action != "" && symbol != "")
        {
         SignalInfo s;
         s.signal_id = signal_id;
         s.action = action;
         s.symbol = symbol;
         s.delay_sec = delay_sec;
         s.raw_json = item;

         if(StringFind(action, "CLOSE") == 0)
           {
            ArrayResize(close_signals, ArraySize(close_signals) + 1);
            close_signals[ArraySize(close_signals) - 1] = s;
           }
         else
           {
            ArrayResize(open_signals, ArraySize(open_signals) + 1);
            open_signals[ArraySize(open_signals) - 1] = s;
           }
         ArrayResize(handled_signals, ArraySize(handled_signals) + 1);
         handled_signals[ArraySize(handled_signals) - 1] = signal_id;
        }

      pos = end + 1;
     }

   for(int i = 0; i < ArraySize(close_signals); i++)
     {
      ProcessSignalNoDelay(close_signals[i].action, close_signals[i].symbol);
     }

   for(int i = 0; i < ArraySize(open_signals); i++)
     {
      if(open_signals[i].delay_sec > 0)
        {
         Print("⏱️ Delay: ", open_signals[i].delay_sec, " saniye bekleniyor...");
         Sleep(open_signals[i].delay_sec * 1000);
        }
      ProcessSignalWithFixedLot(open_signals[i].action, open_signals[i].symbol, lot_for_this_bar);
      bar_icerisinde_artis_yapildi = false;
      // burada ayrıca CloseInstantIfBothSides çağrısı redundant olur, ProcessSignalWithFixedLot içinde zaten var.
     }
  }

//+------------------------------------------------------------------+
//| OnInit - OnDeinit (Timer kurulumu)                               |
//+------------------------------------------------------------------+
int OnInit()
  {
   EventSetTimer(1); // Her 1 sn'de OnTimer çağrılır
   TrackAndLogManualClosures();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

//+------------------------------------------------------------------+
//| OnTimer - bar sonu toplu kapanış ve kuyruk işle                  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   TrackAndLogManualClosures();
   CloseAllPositionsBeforeBarEnd(Symbol());
   ProcessRetryQueue();
  }

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+


double CalculateDynamicStartLot()
  {
   if(!automatic_start_lot_size)
     {
      Print(StringFormat("⚙️ Otomatik lot: PASİF — start_lot_size kullanılacak: %.4f", start_lot_size));
      return start_lot_size;
     }

   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity_reference_value <= 0.0)
     {
      Print("⚠️ Referans equity sıfır veya geçersiz! Otomatik lot hesaplanamaz, default lot kullanılacak.");
      return start_lot_size;
     }

   double ratio = current_equity / equity_reference_value;
   double calculated_lot = NormalizeDouble(start_lot_size * ratio, 2);

   Print(StringFormat(
      "🧮 Otomatik lot hesaplama: (equity %.2f / referans %.2f) = oran %.4f → lot: %.4f",
      current_equity, equity_reference_value, ratio, calculated_lot
   ));

   return calculated_lot;
  }


double CalculateDynamicStartLot()
  {
   if(!automatic_start_lot_size)
     {
      Print(StringFormat("⚙️ Otomatik lot: PASİF — start_lot_size kullanılacak: %.4f", start_lot_size));
      return start_lot_size;
     }

   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity_reference_value <= 0.0)
     {
      Print("⚠️ Referans equity sıfır veya geçersiz! Otomatik lot hesaplanamaz, default lot kullanılacak.");
      return start_lot_size;
     }

   double ratio = current_equity / equity_reference_value;
   double calculated_lot = NormalizeDouble(start_lot_size * ratio, 2);

   Print(StringFormat(
      "🧮 Otomatik lot hesaplama: (equity %.2f / referans %.2f) = oran %.4f → lot: %.4f",
      current_equity, equity_reference_value, ratio, calculated_lot
   ));

   return calculated_lot;
  }
