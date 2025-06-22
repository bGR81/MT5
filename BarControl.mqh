#include <Trade\Trade.mqh>
extern CTrade trade;

void InitBarControl() {}

bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &prev_bar_time)
{
    datetime current_bar = iTime(Symbol(), tf, 0);
    return (current_bar != prev_bar_time);
}

void CheckAndCloseAllPositionsBeforeBarEnd(ENUM_TIMEFRAMES tf, int seconds)
{
    datetime bar_start = iTime(Symbol(), tf, 0);
    int bar_sec = (int)PeriodSeconds(tf);
    int passed = (int)(TimeCurrent() - bar_start);
    int left = bar_sec - passed;
    if (left <= seconds && left > 0)
    {
        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if (PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == Symbol())
            {
                trade.PositionClose(ticket);
                Print("Bar sonu: Tüm pozisyonlar kapatılıyor | Ticket:", ticket);
            }
        }
    }
}