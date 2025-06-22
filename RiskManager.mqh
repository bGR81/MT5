extern double risk_percent_per_trade;

void InitRiskManager() {}

double CalculateDynamicLot()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double contract_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_CONTRACT_SIZE);
    double lot = (balance * risk_percent_per_trade / 100.0) / contract_size;

    lot = MathMax(lot, min_lot);
    lot = MathMin(lot, max_lot);
    lot = NormalizeDouble(lot, 2);

    return lot;
}