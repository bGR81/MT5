extern double current_lot_buy;
extern double current_lot_sell;
extern int martingale_retry_buy;
extern int martingale_retry_sell;
extern double start_lot_size;

void InitMartingale()
{
    current_lot_buy = start_lot_size;
    current_lot_sell = start_lot_size;
    martingale_retry_buy = 0;
    martingale_retry_sell = 0;
}

void ResetBarMartingale()
{
    martingale_retry_buy = 0;
    martingale_retry_sell = 0;
    current_lot_buy = start_lot_size;
    current_lot_sell = start_lot_size;
}

void ResetMartingaleState()
{
    martingale_retry_buy = 0;
    martingale_retry_sell = 0;
    current_lot_buy = start_lot_size;
    current_lot_sell = start_lot_size;
}