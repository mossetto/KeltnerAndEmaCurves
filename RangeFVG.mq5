//+------------------------------------------------------------------+
//| RangeFVG.mq5                                                     |
//| Detecta y dibuja FVG (Fair Value Gap) con toggle por click.      |
//| Alerta multi-symbol cuando se activa.                            |
//+------------------------------------------------------------------+
#property copyright "RangeFVG"
#property version   "1.1"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//============================== INPUTS ===============================
input group  "FVG"
input color  CLR_FVG_BULL = clrLime;
input color  CLR_FVG_BEAR = clrRed;
input int    FVG_BACK     = 0;
input int    LINE_WIDTH   = 2;
input bool   InpFvgMitigOnly = false;
input double InpFvgMitigFrac = 0.55;
input int    InpFvgMitigBars = 4;

input group  "Alertas Multi-Symbol"
input string InpNotifyPairs      = "";           // Only watch these pairs (comma sep)
input bool   InpAlertEnabled     = false;
input bool   InpAlertDesktop     = true;
input bool   InpAlertPushMobile  = true;
input int    InpScanIntervalSec  = 10;

//============================ GLOBALES ==============================
#define PREFIX "RFVG_"

struct FvgBox
{
   string   name;
   datetime t1, t2;
   datetime b1, b2;
   double   pTop, pBot;
   bool     isBull;
};

FvgBox   g_fvg[];
string   g_on[];

double   g_cHigh[], g_cLow[], g_cClose[];
datetime g_cTime[];
int      g_cN = 0;

datetime g_lastScan = 0;
datetime g_alertedBars[200];
string   g_alertedSym[200];
int      g_alertedCount = 0;

string   g_watch[];

//+------------------------------------------------------------------+
bool WasAlerted(string symbol, datetime barTime)
{
   for(int i = 0; i < g_alertedCount; i++)
      if(g_alertedSym[i] == symbol && g_alertedBars[i] == barTime)
         return true;
   return false;
}

void MarkAlerted(string symbol, datetime barTime)
{
   if(g_alertedCount >= 190) g_alertedCount = 0;
   g_alertedSym[g_alertedCount] = symbol;
   g_alertedBars[g_alertedCount] = barTime;
   g_alertedCount++;
}

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "RangeFVG");
   ArraySetAsSeries(g_cHigh, true); ArraySetAsSeries(g_cLow, true);
   ArraySetAsSeries(g_cClose, true); ArraySetAsSeries(g_cTime, true);

   ArrayResize(g_watch, 0);
   if(InpNotifyPairs != "") {
      string list = InpNotifyPairs;
      for(;;) {
         int pos = StringFind(list, ",");
         string s = (pos >= 0) ? StringSubstr(list, 0, pos) : list;
         StringTrimRight(s); StringTrimLeft(s);
         if(s != "") {
            int m = ArraySize(g_watch);
            ArrayResize(g_watch, m + 1);
            g_watch[m] = s;
         }
         if(pos < 0) break;
         list = StringSubstr(list, pos + 1);
      }
   }

   if(InpAlertEnabled)
   {
      string testMsg = StringFormat("RangeFVG Activated in %s | TF: %s",
                                    _Symbol,
                                    StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7));
      if(InpAlertDesktop) Alert(testMsg);
      if(InpAlertPushMobile) SendNotification(testMsg);
   }
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX);
}

//+------------------------------------------------------------------+
bool IsToggled(string nm)
{
   for(int i = 0; i < ArraySize(g_on); i++)
      if(g_on[i] == nm) return true;
   return false;
}

void ToggleName(string nm)
{
   for(int i = 0; i < ArraySize(g_on); i++)
   {
      if(g_on[i] == nm)
      {
         int last = ArraySize(g_on) - 1;
         g_on[i] = g_on[last];
         ArrayResize(g_on, last);
         return;
      }
   }
   int m = ArraySize(g_on);
   ArrayResize(g_on, m + 1);
   g_on[m] = nm;
}

//+------------------------------------------------------------------+
void RegFvg(string nm, datetime t1, datetime t2, datetime b1, datetime b2,
            double pTop, double pBot, bool isBull)
{
   int m = ArraySize(g_fvg);
   ArrayResize(g_fvg, m + 1);
   g_fvg[m].name   = nm;
   g_fvg[m].t1     = t1;
   g_fvg[m].t2     = t2;
   g_fvg[m].b1     = b1;
   g_fvg[m].b2     = b2;
   g_fvg[m].pTop   = pTop;
   g_fvg[m].pBot   = pBot;
   g_fvg[m].isBull = isBull;
}

//+------------------------------------------------------------------+
void MakeRect(string nm, datetime t1, datetime t2, double p1, double p2, color clr)
{
   ObjectDelete(0, nm);
   if(!ObjectCreate(0, nm, OBJ_RECTANGLE, 0, t1, p1, t2, p2)) return;
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_FILL, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
}

//+------------------------------------------------------------------+
void MakeLine(string nm, datetime t1, datetime t2, double price, color clr)
{
   ObjectDelete(0, nm);
   if(!ObjectCreate(0, nm, OBJ_TREND, 0, t1, price, t2, price)) return;
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, LINE_WIDTH);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, nm, OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
datetime FindTouchFVG(const MqlRates &bars[], int n, int startIdx, double level)
{
   for(int j = startIdx; j < n; j++)
      if(bars[j].low <= level && level <= bars[j].high)
         return bars[j].time;
   return bars[n - 1].time;
}

//+------------------------------------------------------------------+
void DrawFvgLines(string fvgName, bool isBull, double pTop, double pBot,
                  datetime tStart, const MqlRates &bars[], int n, int kFvg)
{
   color topColor = isBull ? CLR_FVG_BULL : CLR_FVG_BEAR;
   color botColor = isBull ? CLR_FVG_BEAR : CLR_FVG_BULL;
   datetime tTop = FindTouchFVG(bars, n, kFvg + 3, pTop);
   datetime tBot = FindTouchFVG(bars, n, kFvg + 3, pBot);
   MakeLine(fvgName + "_LT", tStart, tTop, pTop, topColor);
   MakeLine(fvgName + "_LB", tStart, tBot, pBot, botColor);
}

//+------------------------------------------------------------------+
double MitigFracBull(const MqlRates &bars[], int n, int fvgEnd, double pBot, double pTop)
{
   double worstLow = pTop;
   int limit = MathMin(n, fvgEnd + InpFvgMitigBars);
   for(int j = fvgEnd; j < limit; j++)
      if(bars[j].low < worstLow) worstLow = bars[j].low;
   if(worstLow >= pTop) return 0;
   return (pTop - worstLow) / (pTop - pBot);
}

double MitigFracBear(const MqlRates &bars[], int n, int fvgEnd, double pBot, double pTop)
{
   double worstHigh = pBot;
   int limit = MathMin(n, fvgEnd + InpFvgMitigBars);
   for(int j = fvgEnd; j < limit; j++)
      if(bars[j].high > worstHigh) worstHigh = bars[j].high;
   if(worstHigh <= pBot) return 0;
   return (worstHigh - pBot) / (pTop - pBot);
}

//+------------------------------------------------------------------+
void DrawFVGs()
{
   MqlRates bars[];
   ArraySetAsSeries(bars, false);
   int want = (FVG_BACK > 0) ? MathMin(FVG_BACK, Bars(_Symbol, PERIOD_CURRENT))
                             : Bars(_Symbol, PERIOD_CURRENT);
   int n = CopyRates(_Symbol, PERIOD_CURRENT, 0, want, bars);
   if(n < 3) return;

   ArrayResize(g_fvg, 0);
   long pSec = PeriodSeconds(PERIOD_CURRENT);

   for(int k = 0; k <= n - 3; k++)
   {
      datetime t1 = (datetime)(bars[k].time     + pSec / 2);
      datetime t2 = (datetime)(bars[k + 2].time + pSec / 2);

      // --- BULLISH FVG ---
      if(bars[k + 2].low > bars[k].high)
      {
         double pTop = bars[k + 2].low;
         double pBot = bars[k].high;
         if(InpFvgMitigOnly)
         {
            double frac = MitigFracBull(bars, n, k + 3, pBot, pTop);
            if(frac < InpFvgMitigFrac) { /* skip */ }
            else { /* dibuja igual */ }
         }
         string nm = PREFIX + "FB_" + TimeToString(bars[k].time, TIME_DATE|TIME_MINUTES);
         MakeRect(nm, t1, t2, pBot, pTop, CLR_FVG_BULL);
         RegFvg(nm, t1, t2, bars[k].time, bars[k + 2].time, pTop, pBot, true);
         if(IsToggled(nm))
            DrawFvgLines(nm, true, pTop, pBot, t2, bars, n, k);
      }

      // --- BEARISH FVG ---
      if(bars[k + 2].high < bars[k].low)
      {
         double pTop = bars[k].low;
         double pBot = bars[k + 2].high;
         if(InpFvgMitigOnly)
         {
            double frac = MitigFracBear(bars, n, k + 3, pBot, pTop);
            if(frac < InpFvgMitigFrac) { /* skip */ }
            else { /* dibuja igual */ }
         }
         string nm = PREFIX + "FS_" + TimeToString(bars[k].time, TIME_DATE|TIME_MINUTES);
         MakeRect(nm, t1, t2, pBot, pTop, CLR_FVG_BEAR);
         RegFvg(nm, t1, t2, bars[k].time, bars[k + 2].time, pTop, pBot, false);
         if(IsToggled(nm))
            DrawFvgLines(nm, false, pTop, pBot, t2, bars, n, k);
      }
   }
}

//+------------------------------------------------------------------+
void LoadChartOHLC()
{
   int cn = MathMin(50000, Bars(_Symbol, PERIOD_CURRENT));
   g_cN = 0;
   if(cn < 10) return;
   int h = CopyHigh(_Symbol, PERIOD_CURRENT, 0, cn, g_cHigh);
   int l = CopyLow(_Symbol, PERIOD_CURRENT, 0, cn, g_cLow);
   int c = CopyClose(_Symbol, PERIOD_CURRENT, 0, cn, g_cClose);
   int t = CopyTime(_Symbol, PERIOD_CURRENT, 0, cn, g_cTime);
   g_cN = MathMin(MathMin(MathMin(h, l), c), t);
}

//+------------------------------------------------------------------+
void DrawAll()
{
   ObjectsDeleteAll(0, PREFIX);
   LoadChartOHLC();
   DrawFVGs();
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//--- ALERTAS MULTI-SYMBOL ---
bool IsFVGConfirmed(const string &symbol, ENUM_TIMEFRAMES tf, datetime &confirmTime)
{
   MqlRates bars[];
   ArraySetAsSeries(bars, false);
   int n = CopyRates(symbol, tf, 0, 4, bars);
   if(n < 4) return false;

   confirmTime = bars[2].time; // tercera vela (indice 2 = k+2)

   // Indices: 0=base, 1=gap, 2=confirmacion, 3=actual
   // bull: bars[2].low > bars[0].high
   // bear: bars[2].high < bars[0].low
   bool bullFVG = bars[2].low > bars[0].high;
   bool bearFVG = bars[2].high < bars[0].low;

   if(!bullFVG && !bearFVG) return false;

   // Confirmacion: tercera vela (indice 2) cerro sin rellenar el gap
   if(bullFVG)
   {
      if(bars[2].close <= bars[0].high) return false;
      return true;
   }
   else
   {
      if(bars[2].close >= bars[0].low) return false;
      return true;
   }
}

void CheckWatchedSymbols()
{
   if(!InpAlertEnabled) return;
   if(InpNotifyPairs == "" || ArraySize(g_watch) == 0) return;

   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
   string tfName = StringSubstr(EnumToString(tf), 7);

   for(int i = 0; i < ArraySize(g_watch); i++)
   {
      string symbol = g_watch[i];
      datetime confirmTime = 0;
      if(!IsFVGConfirmed(symbol, tf, confirmTime)) continue;
      if(WasAlerted(symbol, confirmTime)) continue;
      MarkAlerted(symbol, confirmTime);

      string msg = StringFormat("FVG CONFIRMADO | Par: %s | TF: %s | Hora: %s",
                                symbol, tfName,
                                TimeToString(confirmTime, TIME_DATE|TIME_SECONDS));

      if(InpAlertDesktop) Alert(msg);
      if(InpAlertPushMobile)
      {
         if(SendNotification(msg))
            Print("[RangeFVG] Push: ", symbol);
      }
   }
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_CLICK) return;
   int sub = 0; datetime t = 0; double price = 0;
   if(!ChartXYToTimePrice(0, (int)lparam, (int)dparam, sub, t, price)) return;
   if(sub != 0) return;

   for(int i = 0; i < ArraySize(g_fvg); i++)
   {
      if(t >= g_fvg[i].t1 && t <= g_fvg[i].t2 &&
         price <= g_fvg[i].pTop && price >= g_fvg[i].pBot)
      {
         ToggleName(g_fvg[i].name);
         DrawAll();
         return;
      }
   }
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   static datetime lastBar = 0;
   datetime cur = time[rates_total - 1];

   if(prev_calculated == 0 || cur != lastBar)
   {
      DrawAll();
      lastBar = cur;
   }

   // Alertas multi-symbol
   if(InpAlertEnabled)
   {
      if(g_alertedCount >= 190) g_alertedCount = 0;
      datetime now = TimeCurrent();
      if(now - g_lastScan >= InpScanIntervalSec)
      {
         g_lastScan = now;
         CheckWatchedSymbols();
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+
