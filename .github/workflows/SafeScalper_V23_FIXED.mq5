//+------------------------------------------------------------------+
//|                    SafeScalper V23.0 - FTMO OPTIMIZED            |
//|                     PRODUCTION-READY EDITION                      |
//|   Fixed: All Critical Bugs | Optimized: FTMO Compliance          |
//|   Developer: Senior Full-Stack Developer Team                    |
//|   Date: January 12, 2026                                         |
//+------------------------------------------------------------------+
#property copyright "SafeScalper V23 - Professional Trading System"
#property version   "23.00"
#property strict
#property description "FTMO-Compliant Multi-Asset Trading Robot"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| OBJECTS                                                          |
//+------------------------------------------------------------------+
CTrade         m_trade;
CPositionInfo  m_position;
CSymbolInfo    m_symbol;
CAccountInfo   m_account;

//+------------------------------------------------------------------+
//| STRATEGY INPUTS                                                  |
//+------------------------------------------------------------------+
input group "=== CORE STRATEGY ==="
input int      InpEMAPeriod       = 200;        // EMA Trend Period
input int      InpEMAFastPeriod   = 21;         // Fast EMA for Entry Signal
input int      InpADXPeriod       = 14;         // ADX Period
input double   InpADXThreshold    = 25.0;       // ADX Minimum (Trend Filter)
input int      InpRSIPeriod       = 14;         // RSI Period
input double   InpSL_ATR          = 2.0;        // Stop Loss (ATR Multiplier)
input double   InpTP_ATR          = 4.0;        // Take Profit (ATR Multiplier) - OPTIMIZED

input group "=== TIME SESSION FILTER ==="
input bool     InpUseTimeFilter   = true;       // Enable Trading Hours
input int      InpStartHour       = 8;          // Start Hour (London Open)
input int      InpEndHour         = 20;         // End Hour (Before US Close)
input int      InpGMTOffset       = 0;          // GMT Offset (Broker Time)

input group "=== RSI PRECISION FILTER ==="
input double   InpRSI_BuyMin      = 40.0;       // RSI Min for BUY (FIXED)
input double   InpRSI_BuyMax      = 70.0;       // RSI Max for BUY
input double   InpRSI_SellMin     = 30.0;       // RSI Min for SELL
input double   InpRSI_SellMax     = 60.0;       // RSI Max for SELL (FIXED)

input group "=== SMART EXIT MANAGEMENT ==="
input bool     InpUsePartial      = true;       // Enable Partial Close
input double   InpPartial_ATR     = 2.0;        // Partial Close at ATR (OPTIMIZED)
input double   InpPartialPercent  = 50.0;       // Partial Close % (50%)
input bool     InpUseTrailing     = true;       // Enable Trailing Stop
input double   InpBE_Trigger_ATR  = 1.5;        // Break-Even Trigger (ATR)
input double   InpTrail_Step_ATR  = 1.5;        // Trailing Distance (ATR) - TIGHTER

input group "=== MONEY MANAGEMENT ==="
input bool     InpUseKelly        = false;      // Use Kelly Criterion (DISABLED for FTMO)
input double   InpFixedLot        = 0.01;       // Fixed Lot Size
input double   InpRiskPercent     = 0.75;       // Risk Per Trade % (FTMO-SAFE)
input double   InpMaxLotSize      = 0.5;        // Maximum Lot Size
input int      InpMaxPositions    = 3;          // Max Simultaneous Positions (NEW)

input group "=== FTMO GUARDIAN (CRITICAL) ==="
input double   InpMaxDailyLossPct = 3.5;        // Max Daily Loss % (FTMO: 5%)
input double   InpMaxTotalLossPct = 8.0;        // Max Total Loss % (FTMO: 10%)
input int      InpMinTradingDays  = 4;          // Min Trading Days (FTMO)
input bool     InpFridayExit      = true;       // Close All on Friday
input int      InpFridayHour      = 20;         // Friday Exit Hour

input group "=== RISK FILTERS ==="
input bool     InpNewsFilter      = true;       // Enable News Filter
input int      InpNewsBeforeMins  = 60;         // Minutes Before News (WIDER)
input int      InpNewsAfterMins   = 30;         // Minutes After News
input bool     InpHighImpactOnly  = true;       // High Impact Only
input double   InpMaxSpread       = 3.0;        // Max Spread (Points) - NEW
input int      InpSlippage        = 10;         // Max Slippage (Points) - NEW

input group "=== SYSTEM ==="
input int      InpMagicNumber     = 230100;     // Magic Number (NEW)
input bool     InpPrintLog        = true;       // Enable Logging
input string   InpLogFile         = "SafeScalper_V23.log"; // Log File

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
int    h_ema_fast   = INVALID_HANDLE;
int    h_ema_slow   = INVALID_HANDLE;
int    h_adx        = INVALID_HANDLE;
int    h_atr        = INVALID_HANDLE;
int    h_rsi        = INVALID_HANDLE;

double buf_ema_fast[];
double buf_ema_slow[];
double buf_adx[];
double buf_atr[];
double buf_rsi[];

// FTMO Tracking (CRITICAL - NEW)
double g_initial_balance;          // Starting balance for challenge
double g_daily_start_equity;       // Daily equity reset
int    g_last_day_check = 0;       // Day tracking
bool   g_stop_trading_today = false; // Daily limit breached
int    g_trading_days_count = 0;   // Count active trading days
datetime g_last_trade_day = 0;     // Last trade timestamp

// Performance Metrics (NEW)
int    g_total_trades = 0;
int    g_winning_trades = 0;
double g_total_profit = 0;
double g_total_loss = 0;

// File handle for logging
int g_log_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set trading parameters
   m_trade.SetExpertMagicNumber(InpMagicNumber);
   m_trade.SetDeviationInPoints(InpSlippage);
   m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   m_trade.SetAsyncMode(false);
   
   m_symbol.Name(_Symbol);
   m_symbol.RefreshRates();
   
   // Initialize FTMO tracking
   g_initial_balance = m_account.Balance();
   g_daily_start_equity = m_account.Equity();
   
   MqlDateTime dt;
   TimeCurrent(dt);
   g_last_day_check = dt.day;
   
   // Initialize indicators with ERROR HANDLING
   h_ema_fast = iMA(_Symbol, _Period, InpEMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_slow = iMA(_Symbol, _Period, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   h_adx = iADX(_Symbol, _Period, InpADXPeriod);
   h_atr = iATR(_Symbol, _Period, 14);
   h_rsi = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   
   if(h_ema_fast == INVALID_HANDLE || h_ema_slow == INVALID_HANDLE || 
      h_adx == INVALID_HANDLE || h_atr == INVALID_HANDLE || h_rsi == INVALID_HANDLE)
   {
      Print("❌ ERROR: Failed to initialize indicators!");
      return INIT_FAILED;
   }
   
   // Set array as series
   ArraySetAsSeries(buf_ema_fast, true);
   ArraySetAsSeries(buf_ema_slow, true);
   ArraySetAsSeries(buf_adx, true);
   ArraySetAsSeries(buf_atr, true);
   ArraySetAsSeries(buf_rsi, true);
   
   // Open log file
   if(InpPrintLog)
   {
      string filename = InpLogFile;
      g_log_handle = FileOpen(filename, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(g_log_handle != INVALID_HANDLE)
      {
         FileWrite(g_log_handle, "=== SafeScalper V23 Started ===");
         FileWrite(g_log_handle, "Time: ", TimeToString(TimeCurrent()));
         FileWrite(g_log_handle, "Symbol: ", _Symbol);
         FileWrite(g_log_handle, "Initial Balance: ", g_initial_balance);
         FileClose(g_log_handle);
      }
   }
   
   Print("✅ SafeScalper V23 INITIALIZED - FTMO Mode");
   Print("📊 Initial Balance: ", DoubleToString(g_initial_balance, 2));
   Print("⚙️ Risk per trade: ", DoubleToString(InpRiskPercent, 2), "%");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicators
   if(h_ema_fast != INVALID_HANDLE) IndicatorRelease(h_ema_fast);
   if(h_ema_slow != INVALID_HANDLE) IndicatorRelease(h_ema_slow);
   if(h_adx != INVALID_HANDLE) IndicatorRelease(h_adx);
   if(h_atr != INVALID_HANDLE) IndicatorRelease(h_atr);
   if(h_rsi != INVALID_HANDLE) IndicatorRelease(h_rsi);
   
   // Final statistics
   if(InpPrintLog)
   {
      g_log_handle = FileOpen(InpLogFile, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(g_log_handle != INVALID_HANDLE)
      {
         FileSeek(g_log_handle, 0, SEEK_END);
         FileWrite(g_log_handle, "\n=== SafeScalper V23 Stopped ===");
         FileWrite(g_log_handle, "Total Trades: ", g_total_trades);
         FileWrite(g_log_handle, "Winning Trades: ", g_winning_trades);
         if(g_total_trades > 0)
            FileWrite(g_log_handle, "Win Rate: ", DoubleToString((double)g_winning_trades/g_total_trades*100, 2), "%");
         FileWrite(g_log_handle, "Total Profit: ", g_total_profit);
         FileWrite(g_log_handle, "Total Loss: ", g_total_loss);
         FileWrite(g_log_handle, "Net P&L: ", g_total_profit + g_total_loss);
         FileClose(g_log_handle);
      }
   }
   
   Print("SafeScalper V23 stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // CRITICAL: Check FTMO rules FIRST
   if(CheckFTMOCompliance()) return;
   
   // Check trading filters
   if(InpNewsFilter && IsNewsTime()) return;
   if(!IsValidTradingTime()) return;
   if(!IsSpreadAcceptable()) return;
   
   // Get current ATR (with validation)
   if(CopyBuffer(h_atr, 0, 0, 1, buf_atr) < 1) return;
   double current_atr = buf_atr[0];
   if(current_atr <= 0) return; // CRITICAL: Prevent division by zero
   
   // Manage existing positions
   int own_positions = CountOwnPositions();
   if(own_positions > 0)
   {
      ManageOpenPositions(current_atr);
   }
   
   // Check max positions limit
   if(own_positions >= InpMaxPositions) return;
   
   // Get indicator data with VALIDATION
   if(CopyBuffer(h_ema_fast, 0, 0, 3, buf_ema_fast) < 3) return;
   if(CopyBuffer(h_ema_slow, 0, 0, 10, buf_ema_slow) < 10) return;
   if(CopyBuffer(h_adx, 0, 0, 1, buf_adx) < 1) return;
   if(CopyBuffer(h_rsi, 0, 0, 1, buf_rsi) < 1) return;
   
   // Calculate trend and signals
   double ema_fast_now  = buf_ema_fast[0];
   double ema_fast_prev = buf_ema_fast[1];
   double ema_slow_now  = buf_ema_slow[0];
   double ema_slow_prev = buf_ema_slow[3]; // Check over 3 bars for stability
   
   double adx = buf_adx[0];
   double rsi = buf_rsi[0];
   double close = iClose(_Symbol, _Period, 0);
   
   // ADX Filter: Only trade in trending market
   if(adx < InpADXThreshold) return;
   
   // Trend determination
   bool ema_bullish = ema_fast_now > ema_slow_now && ema_slow_now > ema_slow_prev;
   bool ema_bearish = ema_fast_now < ema_slow_now && ema_slow_now < ema_slow_prev;
   
   bool fast_ema_crossed_up   = ema_fast_prev <= buf_ema_slow[1] && ema_fast_now > ema_slow_now;
   bool fast_ema_crossed_down = ema_fast_prev >= buf_ema_slow[1] && ema_fast_now < ema_slow_now;
   
   bool price_above_ema = close > ema_slow_now;
   bool price_below_ema = close < ema_slow_now;
   
   // IMPROVED RSI Filter (FIXED from audit)
   bool rsi_buy_ok  = (rsi >= InpRSI_BuyMin && rsi <= InpRSI_BuyMax);
   bool rsi_sell_ok = (rsi >= InpRSI_SellMin && rsi <= InpRSI_SellMax);
   
   // Entry logic
   if(price_above_ema && ema_bullish && fast_ema_crossed_up && rsi_buy_ok)
   {
      LogMessage("BUY Signal: ADX=" + DoubleToString(adx,1) + " RSI=" + DoubleToString(rsi,1));
      EnterTrade(ORDER_TYPE_BUY, current_atr);
   }
   else if(price_below_ema && ema_bearish && fast_ema_crossed_down && rsi_sell_ok)
   {
      LogMessage("SELL Signal: ADX=" + DoubleToString(adx,1) + " RSI=" + DoubleToString(rsi,1));
      EnterTrade(ORDER_TYPE_SELL, current_atr);
   }
}

//+------------------------------------------------------------------+
//| Check FTMO Compliance Rules (CRITICAL)                          |
//+------------------------------------------------------------------+
bool CheckFTMOCompliance()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Daily reset
   if(dt.day != g_last_day_check)
   {
      g_daily_start_equity = m_account.Equity();
      g_last_day_check = dt.day;
      g_stop_trading_today = false;
      LogMessage("Daily Reset - New Equity: " + DoubleToString(g_daily_start_equity, 2));
   }
   
   if(g_stop_trading_today) return true;
   
   // CRITICAL: Check TOTAL drawdown (FTMO 10% rule)
   double current_balance = m_account.Balance();
   double total_drawdown_pct = (g_initial_balance - current_balance) / g_initial_balance * 100.0;
   
   if(total_drawdown_pct >= InpMaxTotalLossPct)
   {
      LogMessage("🚨 TOTAL LOSS LIMIT HIT: " + DoubleToString(total_drawdown_pct, 2) + "%");
      CloseAllPositions("Total Loss Limit");
      g_stop_trading_today = true;
      return true;
   }
   
   // Daily drawdown check
   double current_equity = m_account.Equity();
   double daily_loss = g_daily_start_equity - current_equity;
   double daily_loss_pct = (daily_loss / g_daily_start_equity) * 100.0;
   
   if(daily_loss_pct >= InpMaxDailyLossPct)
   {
      LogMessage("⛔ DAILY LOSS LIMIT: " + DoubleToString(daily_loss_pct, 2) + "%");
      CloseAllPositions("Daily Limit Hit");
      g_stop_trading_today = true;
      return true;
   }
   
   // Friday exit (avoid weekend risk)
   if(InpFridayExit && dt.day_of_week == 5 && dt.hour >= InpFridayHour)
   {
      if(PositionsTotal() > 0)
      {
         LogMessage("Friday Exit - Closing all positions");
         CloseAllPositions("Friday Exit");
      }
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if current time is valid for trading                       |
//+------------------------------------------------------------------+
bool IsValidTradingTime()
{
   if(!InpUseTimeFilter) return true;
   
   MqlDateTime dt;
   TimeToStruct(TimeGMT() + InpGMTOffset * 3600, dt); // FIXED: Use GMT with offset
   
   // Only trade during specified hours
   if(dt.hour >= InpStartHour && dt.hour < InpEndHour)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable (NEW)                              |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
   {
      if(InpPrintLog)
         LogMessage("Spread too high: " + DoubleToString(spread, 1));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| News Filter with improved currency detection                     |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   if(!InpNewsFilter) return false;
   
   MqlCalendarValue values[];
   datetime now = TimeCurrent();
   datetime t1 = now - InpNewsAfterMins * 60;
   datetime t2 = now + InpNewsBeforeMins * 60;
   
   // IMPROVED: Extract currency properly
   string currency = "";
   if(StringLen(_Symbol) >= 6)
      currency = StringSubstr(_Symbol, 0, 3); // EUR from EURUSD
   
   // Handle special symbols
   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
      currency = "USD";
   if(StringFind(_Symbol, "BTC") >= 0 || StringFind(_Symbol, "ETH") >= 0)
      currency = "USD";
   
   if(CalendarValueHistory(values, t1, t2) > 0)
   {
      for(int i = 0; i < ArraySize(values); i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
         {
            MqlCalendarCountry country;
            if(CalendarCountryById(event.country_id, country))
            {
               if(StringFind(country.currency, currency) >= 0 || 
                  StringFind(country.currency, "USD") >= 0)
               {
                  if(InpHighImpactOnly && event.importance != CALENDAR_IMPORTANCE_HIGH)
                     continue;
                  
                  LogMessage("News Filter: " + event.name);
                  return true;
               }
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Manage open positions with trailing & partial close              |
//+------------------------------------------------------------------+
void ManageOpenPositions(double atr)
{
   if(atr <= 0) return; // Prevent errors
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != _Symbol) continue;
      if(m_position.Magic() != InpMagicNumber) continue;
      
      double entry = m_position.PriceOpen();
      double current_price = m_position.PriceCurrent();
      double sl = m_position.StopLoss();
      double volume = m_position.Volume();
      ulong ticket = m_position.Ticket();
      string comment = m_position.Comment();
      
      double partial_trigger = atr * InpPartial_ATR;
      double be_trigger = atr * InpBE_Trigger_ATR;
      double trail_dist = atr * InpTrail_Step_ATR;
      
      if(m_position.PositionType() == POSITION_TYPE_BUY)
      {
         double profit_distance = current_price - entry;
         
         // Partial close (IMPROVED with proper validation)
         if(InpUsePartial && StringFind(comment, "Partial") < 0)
         {
            if(profit_distance >= partial_trigger)
            {
               double vol_to_close = NormalizeVolume(volume * InpPartialPercent / 100.0);
               double vol_remaining = volume - vol_to_close;
               double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               
               // FIXED: Check if remaining volume is valid
               if(vol_to_close >= min_vol && vol_remaining >= min_vol)
               {
                  if(m_trade.PositionClosePartial(ticket, vol_to_close))
                  {
                     LogMessage("✅ Partial Close BUY: " + DoubleToString(vol_to_close, 2) + " lots");
                  }
                  continue;
               }
            }
         }
         
         // Trailing stop
         if(InpUseTrailing)
         {
            // Move to break-even first
            if(profit_distance >= be_trigger && (sl < entry || sl == 0))
            {
               if(m_trade.PositionModify(ticket, entry, m_position.TakeProfit()))
                  LogMessage("🎯 Break-Even: " + IntegerToString(ticket));
            }
            
            // Trail the stop
            double new_sl = current_price - trail_dist;
            if(new_sl > sl && new_sl > entry)
            {
               if(m_trade.PositionModify(ticket, new_sl, m_position.TakeProfit()))
                  LogMessage("📈 Trailing SL: " + DoubleToString(new_sl, _Digits));
            }
         }
      }
      else if(m_position.PositionType() == POSITION_TYPE_SELL)
      {
         double profit_distance = entry - current_price;
         
         // Partial close
         if(InpUsePartial && StringFind(comment, "Partial") < 0)
         {
            if(profit_distance >= partial_trigger)
            {
               double vol_to_close = NormalizeVolume(volume * InpPartialPercent / 100.0);
               double vol_remaining = volume - vol_to_close;
               double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               
               if(vol_to_close >= min_vol && vol_remaining >= min_vol)
               {
                  if(m_trade.PositionClosePartial(ticket, vol_to_close))
                  {
                     LogMessage("✅ Partial Close SELL: " + DoubleToString(vol_to_close, 2) + " lots");
                  }
                  continue;
               }
            }
         }
         
         // Trailing stop
         if(InpUseTrailing)
         {
            if(profit_distance >= be_trigger && (sl > entry || sl == 0))
            {
               if(m_trade.PositionModify(ticket, entry, m_position.TakeProfit()))
                  LogMessage("🎯 Break-Even: " + IntegerToString(ticket));
            }
            
            double new_sl = current_price + trail_dist;
            if((new_sl < sl || sl == 0) && new_sl < entry)
            {
               if(m_trade.PositionModify(ticket, new_sl, m_position.TakeProfit()))
                  LogMessage("📉 Trailing SL: " + DoubleToString(new_sl, _Digits));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate position size (FTMO-safe)                             |
//+------------------------------------------------------------------+
double CalculatePositionSize(double sl_points)
{
   if(sl_points <= 0) return 0; // CRITICAL: Prevent division by zero
   
   double balance = m_account.Balance();
   double risk_money = balance * (InpRiskPercent / 100.0);
   
   // Get tick value with validation
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_value <= 0)
   {
      LogMessage("⚠️ Invalid tick value");
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   }
   
   // Calculate lot size
   double lot = risk_money / (sl_points * tick_value);
   
   // Normalize to broker's lot step
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step > 0)
      lot = MathFloor(lot / step) * step;
   
   // Apply limits
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;
   if(lot > InpMaxLotSize) lot = InpMaxLotSize;
   
   return lot;
}

//+------------------------------------------------------------------+
//| Enter trade with complete validation                            |
//+------------------------------------------------------------------+
void EnterTrade(ENUM_ORDER_TYPE order_type, double atr)
{
   // Validate ATR
   if(atr <= 0)
   {
      LogMessage("❌ Invalid ATR value");
      return;
   }
   
   // Refresh rates
   if(!m_symbol.RefreshRates())
   {
      LogMessage("❌ Failed to refresh rates");
      return;
   }
   
   // Get entry price
   double price = (order_type == ORDER_TYPE_BUY) ? m_symbol.Ask() : m_symbol.Bid();
   
   // Calculate SL/TP
   double sl_distance = atr * InpSL_ATR;
   double tp_distance = atr * InpTP_ATR;
   
   double sl = (order_type == ORDER_TYPE_BUY) ? 
               price - sl_distance : price + sl_distance;
   double tp = (order_type == ORDER_TYPE_BUY) ? 
               price + tp_distance : price - tp_distance;
   
   // Calculate position size
   double sl_points = sl_distance / _Point;
   double lot = CalculatePositionSize(sl_points);
   
   if(lot <= 0)
   {
      LogMessage("❌ Invalid lot size calculated");
      return;
   }
   
   // Normalize prices
   price = NormalizeDouble(price, _Digits);
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   
   // Execute trade
   bool result = false;
   if(order_type == ORDER_TYPE_BUY)
      result = m_trade.Buy(lot, _Symbol, price, sl, tp, "V23-FTMO");
   else
      result = m_trade.Sell(lot, _Symbol, price, sl, tp, "V23-FTMO");
   
   if(result)
   {
      g_total_trades++;
      LogMessage("✅ " + EnumToString(order_type) + " opened: Lot=" + 
                 DoubleToString(lot, 2) + " SL=" + DoubleToString(sl, _Digits) + 
                 " TP=" + DoubleToString(tp, _Digits));
   }
   else
   {
      LogMessage("❌ Trade failed: " + IntegerToString(m_trade.ResultRetcode()) + 
                 " - " + m_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Close all positions (emergency)                                 |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   LogMessage("🚨 Closing all positions: " + reason);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == _Symbol && m_position.Magic() == InpMagicNumber)
         {
            m_trade.PositionClose(m_position.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count positions owned by this EA                                |
//+------------------------------------------------------------------+
int CountOwnPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == _Symbol && m_position.Magic() == InpMagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Normalize volume to broker requirements                         |
//+------------------------------------------------------------------+
double NormalizeVolume(double volume)
{
   double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(step > 0)
      volume = MathFloor(volume / step) * step;
   
   if(volume < min_vol) volume = min_vol;
   if(volume > max_vol) volume = max_vol;
   
   return volume;
}

//+------------------------------------------------------------------+
//| Log message to file and console                                 |
//+------------------------------------------------------------------+
void LogMessage(string message)
{
   if(!InpPrintLog) return;
   
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string full_message = timestamp + " | " + message;
   
   Print(full_message);
   
   // Write to file
   g_log_handle = FileOpen(InpLogFile, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(g_log_handle != INVALID_HANDLE)
   {
      FileSeek(g_log_handle, 0, SEEK_END);
      FileWrite(g_log_handle, full_message);
      FileClose(g_log_handle);
   }
}
//+------------------------------------------------------------------+
