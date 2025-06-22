#include <Trade\Trade.mqh>
#include "Martingale.mqh"
#include "SignalHandler.mqh"
#include "RiskManager.mqh"
#include "PositionManager.mqh"
#include "BarControl.mqh"

CTrade trade;

//--- INPUTS
input string webhook_url_input = "https://webhook-traderx.ngrok.io/getsignal";
input int max_open_buy_input = 1;
input int max_open_sell_input = 1;
input int max_buy_per_bar_input = 4;
input int max_sell_per_bar_input = 4;
input bool enable_auto_risk_input = false;
input double risk_percent_per_trade_input = 1.0;
input double start_lot_size_input = 0.01;
input int max_retries = 3;
input double lot_multiplier = 2.0;
input double profit_threshold_percent = 0.10;
input bool enable_martingale = true;
input double take_profit_pips_input = 50;
input double stop_loss_pips_input = 30;
input ENUM_TIMEFRAMES bar_period = PERIOD_M5;
input bool enable_bar_close_all = false;
input int bar_close_all_seconds = 10;

//--- Global değişkenler
string webhook_url = "";
int max_open_buy = 1;
int max_open_sell = 1;
int max_buy_per_bar = 4;
int max_sell_per_bar = 4;
bool enable_auto_risk = false;
double risk_percent_per_trade = 1.0;
double start_lot_size = 0.01;
double take_profit_pips = 50;
double stop_loss_pips = 30;

//--- Sayaçlar
datetime last_bar_time = 0;
int buy_opened_this_bar = 0;
int sell_opened_this_bar = 0;
int martingale_retry_buy = 0;
int martingale_retry_sell = 0;
double current_lot_buy = 0.01;
double current_lot_sell = 0.01;

int OnInit()
{
    Print("TV Martingale EA başlatıldı!");
    webhook_url = webhook_url_input;
    max_open_buy = max_open_buy_input;
    max_open_sell = max_open_sell_input;
    max_buy_per_bar = max_buy_per_bar_input;
    max_sell_per_bar = max_sell_per_bar_input;
    enable_auto_risk = enable_auto_risk_input;
    risk_percent_per_trade = risk_percent_per_trade_input;
    start_lot_size = start_lot_size_input;
    take_profit_pips = take_profit_pips_input;
    stop_loss_pips = stop_loss_pips_input;

    InitMartingale();
    InitSignalHandler();
    InitRiskManager();
    InitPositionManager();
    InitBarControl();
    last_bar_time = iTime(Symbol(), bar_period, 0);
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
    Print("TV Martingale EA durduruldu.");
}

void OnTick()
{
    if(IsNewBar(bar_period, last_bar_time))
    {
        ResetBarCounters();
        ResetBarMartingale();
        last_bar_time = iTime(Symbol(), bar_period, 0);
    }

    string action = "";
    string tv_symbol = "";
    int    max_open_buy_signal = 0;
    int    max_open_sell_signal = 0;
    long   tv_timestamp = 0;
    bool   got_signal = GetTVSignal(webhook_url, action, tv_symbol, max_open_buy_signal, max_open_sell_signal, tv_timestamp);

    if(enable_bar_close_all) {
        CheckAndCloseAllPositionsBeforeBarEnd(bar_period, bar_close_all_seconds);
    }

    if(got_signal)
    {
        Print("[TV Signal] action: ", action, " | symbol: ", tv_symbol, " | max_buy: ", max_open_buy_signal, " | max_sell: ", max_open_sell_signal, " | ts: ", tv_timestamp, " (", TimeToString((datetime)tv_timestamp, TIME_DATE|TIME_SECONDS), ")");
        HandleSignal(action, tv_symbol, max_open_buy_signal, max_open_sell_signal, tv_timestamp);
    }
}