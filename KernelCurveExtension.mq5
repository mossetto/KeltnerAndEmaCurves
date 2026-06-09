//+------------------------------------------------------------------+
//|                                          KernelCurveExtension.mq5 |
//|  Standalone: calcula EMA50 + ATR20*1.8 internamente.             |
//|  Extension de curvas (pivotes, horizontales, corte dinamico).    |
//+------------------------------------------------------------------+
#property copyright "KernelCurveExtension"
#property version   "2.0"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_label1  "Kernel Mid"
#property indicator_type1   DRAW_NONE

#property indicator_label2  "Kernel Upper"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGray
#property indicator_width2  1

#property indicator_label3  "Kernel Lower"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrGray
#property indicator_width3  1

//============================== INPUTS ===============================
input group  "Kernel Canal"
input int    InpEMAPeriod   = 50;
input int    InpATRPeriod   = 20;
input double InpATRMult     = 1.8;

input group  "Niveles D1"
input bool   InpD1Levels      = false;
input color  InpColUpD1       = clrAqua;
input color  InpColDnD1       = clrOrange;
input color  InpColUpD1b      = clrDeepSkyBlue;
input color  InpColDnD1b      = clrDarkOrange;
input double InpCutSize       = 0.3;

input group  "Deteccion de curvas"
input int    InpMaxBars      = 20000;
input double InpMinCurveFrac = 0.35;

input group  "Extension (chart TF, largo fijo)"
input bool   InpChartTFLevels = true;
input double InpWidthMult    = 1.0;
input bool   InpUseFullWidth = true;
input int    InpProjBars     = 30;
input bool   InpShowParallel = false;
input double InpParallelPct  = 0.25;

input group  "Bandas al impacto"
input bool   InpShowImpactBands = true;
input bool   InpShowBandPar     = false;
input double InpBandParPct       = 25;
input bool   InpOnlyK           = false;

input group  "Visual"
input color  InpColUp = clrLime;
input color  InpColDn = clrRed;
input int    InpWidth  = 2;
input bool   InpShowCurveDot = true;
input int    InpMaxObjects   = 600;

input group  "Debug"
input bool   InpDebug = false;

//============================ GLOBALES ==============================
#define PREFIX "KCE_"

double   g_mid[],  g_up[],  g_dn[];
datetime g_time_m[];

double   g_mid1[], g_up1[], g_dn1[];
datetime g_time1[];

double   g_cHigh[], g_cLow[];
datetime g_cTime[];
int      g_cN = 0;

int      g_drawn = 0;

// Handles nativos (canal estandar: EMA + ATR Wilder)
int      g_hEMA   = INVALID_HANDLE, g_hATR   = INVALID_HANDLE;
int      g_hEMAd1 = INVALID_HANDLE, g_hATRd1 = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "KernelCurveExtension");

   SetIndexBuffer(0, g_mid,  INDICATOR_DATA);
   SetIndexBuffer(1, g_up,   INDICATOR_DATA);
   SetIndexBuffer(2, g_dn,   INDICATOR_DATA);

   ArraySetAsSeries(g_mid,  true);
   ArraySetAsSeries(g_up,   true);
   ArraySetAsSeries(g_dn,   true);
   ArraySetAsSeries(g_time_m, true);
   ArraySetAsSeries(g_mid1, true);
   ArraySetAsSeries(g_up1,  true);
   ArraySetAsSeries(g_dn1,  true);
   ArraySetAsSeries(g_time1, true);
   ArraySetAsSeries(g_cHigh, true);
   ArraySetAsSeries(g_cLow,  true);
   ArraySetAsSeries(g_cTime, true);

   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 0x414141);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, 0x414141);

   // Canal estandar nativo: EMA(close) + ATR Wilder (mismo que el Keltner del market)
   g_hEMA = iMA (_Symbol, _Period, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_hATR = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_hEMA == INVALID_HANDLE || g_hATR == INVALID_HANDLE)
   { Print("[KCE] FALLO iMA/iATR"); return INIT_FAILED; }
   g_hEMAd1 = iMA (_Symbol, PERIOD_D1, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_hATRd1 = iATR(_Symbol, PERIOD_D1, InpATRPeriod);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX);
   if(g_hEMA   != INVALID_HANDLE) IndicatorRelease(g_hEMA);
   if(g_hATR   != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hEMAd1 != INVALID_HANDLE) IndicatorRelease(g_hEMAd1);
   if(g_hATRd1 != INVALID_HANDLE) IndicatorRelease(g_hATRd1);
}

//+------------------------------------------------------------------+
int TotalBars(ENUM_TIMEFRAMES tf)
{
   return (int)SeriesInfoInteger(_Symbol, tf, SERIES_BARS_COUNT);
}

//+------------------------------------------------------------------+
void CalcBands(int total, const double &close[], const double &high[],
               const double &low[], double &mid[], double &up[], double &dn[])
{
   if(total < MathMax(InpEMAPeriod, InpATRPeriod) + 2) return;

   double alpha = 2.0 / (InpEMAPeriod + 1.0);
   int last = total - 1;

   // EMA from oldest to newest
   mid[last] = close[last];
   for(int i = last - 1; i >= 0; i--)
      mid[i] = close[i] * alpha + mid[i+1] * (1.0 - alpha);

   // ATR using Wilder's smoothing
   double tr, sum = 0;
   int atrStart = last - InpATRPeriod;
   if(atrStart < 0) atrStart = 0;

   // Compute first ATR as SMA of first InpATRPeriod TR values
   // TR for oldest bar: high-low (no previous close)
   double trFirst = high[last] - low[last];
   sum = trFirst;
   for(int j = 1; j < InpATRPeriod && last - j >= 0; j++)
   {
      int k = last - j;
      tr = MathMax(high[k] - low[k],
           MathMax(MathAbs(high[k] - close[k+1]),
                   MathAbs(low[k] - close[k+1])));
      sum += tr;
   }
   int atrIdx = last - InpATRPeriod;
   if(atrIdx < 0) atrIdx = 0;
   double prevATR = sum / InpATRPeriod;

   // Fill from atrIdx backwards to 0
   for(int i = last; i >= 0; i--)
   {
      if(i > atrIdx)
      {
         tr = (i == last) ? (high[i] - low[i])
              : MathMax(high[i] - low[i],
                 MathMax(MathAbs(high[i] - close[i+1]),
                         MathAbs(low[i] - close[i+1])));
         dn[i] = 0;
      }
      else if(i == atrIdx)
      {
         dn[i] = prevATR;
      }
      else
      {
         tr = MathMax(high[i] - low[i],
              MathMax(MathAbs(high[i] - close[i+1]),
                      MathAbs(low[i] - close[i+1])));
         dn[i] = (dn[i+1] * (InpATRPeriod - 1) + tr) / InpATRPeriod;
      }
   }
   ArrayCopy(up, dn, 0, 0, WHOLE_ARRAY);

   // Build bands: up = mid + ATR*mult, dn = mid - ATR*mult
   for(int i = last; i >= 0; i--)
   {
      if(dn[i] > 0)
      {
         double atrVal = dn[i];
         up[i] = mid[i] + atrVal * InpATRMult;
         dn[i] = mid[i] - atrVal * InpATRMult;
      }
      else
      {
         up[i] = mid[i];
         dn[i] = mid[i];
      }
   }
}

//+------------------------------------------------------------------+
int CalcBandsOnTF(ENUM_TIMEFRAMES tf, double &mid[], double &up[],
                  double &dn[], datetime &tarr[])
{
   if(g_hEMAd1 == INVALID_HANDLE || g_hATRd1 == INVALID_HANDLE) return 0;
   int total = TotalBars(tf);
   if(total < MathMax(InpEMAPeriod, InpATRPeriod) + 2) return 0;
   int n = MathMin(InpMaxBars, total);

   ArrayResize(mid, n); ArrayResize(up, n); ArrayResize(dn, n);
   ArraySetAsSeries(mid, true); ArraySetAsSeries(up, true); ArraySetAsSeries(dn, true);

   double atr[]; ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_hEMAd1, 0, 0, n, mid) < n) return 0;
   if(CopyBuffer(g_hATRd1, 0, 0, n, atr) < n) return 0;
   if(CopyTime(_Symbol, tf, 0, n, tarr)  < n) return 0;

   for(int i = 0; i < n; i++)
   { up[i] = mid[i] + InpATRMult*atr[i]; dn[i] = mid[i] - InpATRMult*atr[i]; }
   return n;
}

//+------------------------------------------------------------------+
void DetectCurves(const double &mid[], const double &up[], const double &dn[], int n,
                  int &pivIdx[], bool &pivPeak[], int &confIdx[])
{
   ArrayResize(pivIdx, 0);
   ArrayResize(pivPeak, 0);
   ArrayResize(confIdx, 0);

   int extIdx = n - 1;
   double extVal = mid[n - 1];

   int check = MathMin(10, (n-1)/2);
   int dir;
   if(n >= 2 && mid[n-1] < mid[n-1-check])
      dir = -1;  // EMA sube desde el inicio → primero buscar VALLE
   else
      dir = 1;   // EMA baja/plana → primero buscar PICO

   if(InpDebug) PrintFormat("[KCE] DetectCurves n=%d dir=%d mid[%d]=%g mid[%d]=%g",
                            n, dir, n-1, mid[n-1], n-1-check, mid[n-1-check]);

   for(int i = n - 2; i >= 0; i--)
   {
      double v = mid[i];
      double thr = InpMinCurveFrac * MathMax(up[extIdx] - dn[extIdx], _Point);
      if(dir >= 0)
      {
         if(v >= extVal) { extVal = v; extIdx = i; }
         else if(extVal - v >= thr)
         {
            int m = ArraySize(pivIdx);
            ArrayResize(pivIdx, m+1); ArrayResize(pivPeak, m+1); ArrayResize(confIdx, m+1);
            pivIdx[m] = extIdx; pivPeak[m] = true; confIdx[m] = i;
            dir = -1; extVal = v; extIdx = i;
         }
      }
      else
      {
         if(v <= extVal) { extVal = v; extIdx = i; }
         else if(v - extVal >= thr)
         {
            int m = ArraySize(pivIdx);
            ArrayResize(pivIdx, m+1); ArrayResize(pivPeak, m+1); ArrayResize(confIdx, m+1);
            pivIdx[m] = extIdx; pivPeak[m] = false; confIdx[m] = i;
            dir = +1; extVal = v; extIdx = i;
         }
      }
   }
   if(InpDebug) PrintFormat("[KCE] pivots encontrados=%d", ArraySize(pivIdx));
}

//+------------------------------------------------------------------+
datetime FindTouchTime(double level, datetime fromTime, bool levelAbove)
{
   if(g_cN <= 0) return 0;
   for(int i = g_cN - 1; i >= 0; i--)
   {
      if(g_cTime[i] <= fromTime) continue;
      if(levelAbove  && g_cHigh[i] >= level) return g_cTime[i];
      if(!levelAbove && g_cLow[i]  <= level) return g_cTime[i];
   }
   return 0;
}

//+------------------------------------------------------------------+
void DrawCut(string name, datetime t, double level, double halfSize, color clr)
{
   if(halfSize <= 0) return;
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, t, level - halfSize, t, level + halfSize);
   else { ObjectMove(0, name, 0, t, level - halfSize); ObjectMove(0, name, 1, t, level + halfSize); }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
datetime DrawBandLine(string name, datetime tA, double level, datetime fromTime, bool touchHigh, color clr, datetime forceEnd = 0)
{
   if(g_cN <= 0) return 0;
   if(fromTime <= 0) fromTime = tA;

   datetime tt = 0, tB;
   if(forceEnd > 0)  tB = forceEnd;
   else { tt = FindTouchTime(level, fromTime, touchHigh); tB = (tt > 0) ? tt : (g_cN > 0 ? g_cTime[0] : fromTime); }

   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, tA, level, tB, level);
   else { ObjectMove(0, name, 0, tA, level); ObjectMove(0, name, 1, tB, level); }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   if(InpShowCurveDot && tt > 0)
   {
      string dt = name + "_D";
      if(ObjectFind(0, dt) < 0) ObjectCreate(0, dt, OBJ_ARROW, 0, tB, level);
      else                      ObjectMove  (0, dt, 0, tB, level);
      ObjectSetInteger(0, dt, OBJPROP_ARROWCODE, 159);
      ObjectSetInteger(0, dt, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, dt, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, dt, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, dt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, dt, OBJPROP_HIDDEN, true);
   }
   else ObjectDelete(0, name + "_D");
   return tB;
}

//+------------------------------------------------------------------+
void DrawGrayPar(string name, datetime tA, double level, datetime tB)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TREND,0,tA,level,tB,level);
   else { ObjectMove(0,name,0,tA,level); ObjectMove(0,name,1,tB,level); }
   ObjectSetInteger(0,name,OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0,name,OBJPROP_WIDTH, 1);
   ObjectSetInteger(0,name,OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

//+------------------------------------------------------------------+
void DrawExtension(string tag, int ci, double originPrice, double level,
                   double width, color clr, color clrParallel,
                   int n, const datetime &time[], int projBars,
                   bool cutAtTouch, bool x1Parallel,
                   datetime confTime = 0)
{
   datetime tA = time[ci];
   datetime tB;

   bool levelAbove = (level >= originPrice);

   datetime touchFrom = (confTime > 0) ? confTime : tA;
   if(cutAtTouch)
   {
      datetime touchTime = FindTouchTime(level, touchFrom, levelAbove);
      tB = (touchTime > 0) ? touchTime : (g_cN > 0 ? g_cTime[0] : touchFrom);
   }
   else
   {
      int rightIdx = MathMax(0, ci - projBars);
      tB = time[rightIdx];
   }

   string ln = PREFIX + tag + "_X";
   double cutHalf = width * InpCutSize * 0.5;
   if(!InpOnlyK)
   {
      if(ObjectFind(0, ln) < 0) ObjectCreate(0, ln, OBJ_TREND, 0, tA, level, tB, level);
      else { ObjectMove(0, ln, 0, tA, level); ObjectMove(0, ln, 1, tB, level); }
      ObjectSetInteger(0, ln, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, ln, OBJPROP_WIDTH, InpWidth);
      ObjectSetInteger(0, ln, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, ln, OBJPROP_RAY_LEFT,  false);
      ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, ln, OBJPROP_BACK, false);
      ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, ln, OBJPROP_HIDDEN, true);

      if(confTime > 0 && cutHalf > 0)
         DrawCut(PREFIX + tag + "_XC", confTime, level, cutHalf * 0.5, clrWhite);
   }

   string ln2 = PREFIX + tag + "_X2";
   bool doParallel = (x1Parallel || InpShowParallel) && !InpOnlyK;
   if(doParallel && width > 0)
   {
      double dir    = levelAbove ? 1.0 : -1.0;
      double level2;

      if(x1Parallel)
         level2 = level + dir * width;
      else
      {
         double vlen = MathAbs(level - originPrice);
         level2 = level + dir * InpParallelPct * vlen;
      }

      datetime tB2;
      if(cutAtTouch)
      {
         datetime touchTime2 = FindTouchTime(level2, touchFrom, levelAbove);
          tB2 = (touchTime2 > 0) ? touchTime2 : (g_cN > 0 ? g_cTime[0] : touchFrom);
      }
      else
         tB2 = tB;

      if(ObjectFind(0, ln2) < 0) ObjectCreate(0, ln2, OBJ_TREND, 0, tA, level2, tB2, level2);
      else { ObjectMove(0, ln2, 0, tA, level2); ObjectMove(0, ln2, 1, tB2, level2); }
      ObjectSetInteger(0, ln2, OBJPROP_COLOR, clrParallel);
      ObjectSetInteger(0, ln2, OBJPROP_WIDTH, InpWidth);
      ObjectSetInteger(0, ln2, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, ln2, OBJPROP_RAY_LEFT,  false);
      ObjectSetInteger(0, ln2, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, ln2, OBJPROP_BACK, false);
      ObjectSetInteger(0, ln2, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, ln2, OBJPROP_HIDDEN, true);

      if(confTime > 0 && cutHalf > 0)
         DrawCut(PREFIX + tag + "_X2C", confTime, level2, cutHalf, clrParallel);
   }
   else ObjectDelete(0, ln2);

   string cn = PREFIX + tag + "_C";
   if(ObjectFind(0, cn) < 0) ObjectCreate(0, cn, OBJ_TREND, 0, tA, originPrice, tA, level);
   else { ObjectMove(0, cn, 0, tA, originPrice); ObjectMove(0, cn, 1, tA, level); }
   ObjectSetInteger(0, cn, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, cn, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, cn, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, cn, OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0, cn, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, cn, OBJPROP_BACK, false);
   ObjectSetInteger(0, cn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, cn, OBJPROP_HIDDEN, true);

   if(!InpOnlyK)
   {
      string kl  = PREFIX + tag + "_KL";
      string txt = levelAbove ? "KA" : "KB";
      int    anch= levelAbove ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER;
      datetime tk = tA + (datetime)PeriodSeconds();
      if(ObjectFind(0, kl) < 0) ObjectCreate(0, kl, OBJ_TEXT, 0, tk, level);
      else                      ObjectMove  (0, kl, 0, tk, level);
      ObjectSetString (0, kl, OBJPROP_TEXT, txt);
      ObjectSetString (0, kl, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, kl, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, kl, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, kl, OBJPROP_ANCHOR, anch);
      ObjectSetInteger(0, kl, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, kl, OBJPROP_HIDDEN, true);
   }

   if(InpShowCurveDot && !InpOnlyK)
   {
      string dt = PREFIX + tag + "_D";
      if(ObjectFind(0, dt) < 0) ObjectCreate(0, dt, OBJ_ARROW, 0, tA, originPrice);
      else                      ObjectMove  (0, dt, 0, tA, originPrice);
      ObjectSetInteger(0, dt, OBJPROP_ARROWCODE, 159);
      ObjectSetInteger(0, dt, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, dt, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, dt, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, dt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, dt, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
int RebuildTF(double &mid[], double &up[], double &dn[], datetime &time[],
              int n, string srcTag,
              color colUp, color colDn, color colUpP, color colDnP,
              bool cutAtTouch, bool x1Parallel, int projBars)
{
   if(n < 10) return -1;

   int  piv[];
   bool peak[];
   int  conf[];
   DetectCurves(mid, up, dn, n, piv, peak, conf);

   int drawn = 0;
   for(int p = ArraySize(piv) - 1; p >= 0 && g_drawn < InpMaxObjects; p--)
   {
      int  ci = piv[p];
      bool pk = peak[p];
      double width = (InpUseFullWidth ? (up[ci] - dn[ci]) : (up[ci] - mid[ci])) * InpWidthMult;
      if(width <= 0) continue;

      double bandRef = pk ? dn[ci] : up[ci];
      double level   = pk ? (bandRef - width) : (bandRef + width);
      color  clr     = pk ? colDn  : colUp;
      color  clrP    = pk ? colDnP : colUpP;

      string tag = srcTag + (pk ? "P_" : "V_") + IntegerToString(ci);
      datetime confTime = (conf[p] >= 0 && conf[p] < n) ? time[conf[p]] : 0;

      DrawExtension(tag, ci, bandRef, level, width, clr, clrP,
                    n, time, projBars, cutAtTouch, x1Parallel, confTime);

      if(InpShowImpactBands)
      {
         bool     mainAbove = (level >= bandRef);
         datetime impFrom   = (confTime > 0) ? confTime : time[ci];
         datetime impact    = FindTouchTime(level, impFrom, mainAbove);   // ¿se toco la _X?

         double bBand = pk ? up[ci] : dn[ci];
         double bMid  = mid[ci];
         bool   tHigh = pk;
         datetime eBB, eBM;

         if(impact > 0)
         {
            // _X tocada -> BB/BM se extienden hasta su propio toque (o hasta el final)
            eBB = DrawBandLine(PREFIX + tag + "_BB", time[ci], bBand, confTime, tHigh, clr);
            eBM = DrawBandLine(PREFIX + tag + "_BM", time[ci], bMid,  confTime, tHigh, clr);
         }
         else
         {
            // _X NO tocada -> BB/BM se dibujan igual pero cortadas en el tiempo de _XC
            datetime cut = (confTime > 0) ? confTime : time[ci];
            eBB = DrawBandLine(PREFIX + tag + "_BB", time[ci], bBand, confTime, tHigh, clr, cut);
            eBM = DrawBandLine(PREFIX + tag + "_BM", time[ci], bMid,  confTime, tHigh, clr, cut);
         }

         if(InpShowBandPar)
         {
            double offset = MathAbs(bBand - bMid) * (InpBandParPct/100.0);
            double dir    = pk ? +1.0 : -1.0;
            DrawGrayPar(PREFIX + tag + "_BBP", time[ci], bBand + dir*offset, eBB);
            DrawGrayPar(PREFIX + tag + "_BMP", time[ci], bMid  + dir*offset, eBM);
         }
         else { ObjectDelete(0, PREFIX+tag+"_BBP"); ObjectDelete(0, PREFIX+tag+"_BMP"); }
      }

      g_drawn++; drawn++;
   }
   return drawn;
}

//+------------------------------------------------------------------+
bool Rebuild(int count, const datetime &time[])
{
   ObjectsDeleteAll(0, PREFIX);
   g_drawn = 0;

   // Copy times for current TF
   ArrayResize(g_time_m, count);
   for(int i = 0; i < count; i++) g_time_m[i] = time[i];

   // Load OHLC for touch detection
   int cn = MathMin(InpMaxBars, TotalBars(PERIOD_CURRENT));
   g_cN = 0;
   if(cn >= 10)
   {
   int h = CopyHigh(_Symbol, PERIOD_CURRENT, 0, cn, g_cHigh);
   int l = CopyLow (_Symbol, PERIOD_CURRENT, 0, cn, g_cLow);
   int t = CopyTime(_Symbol, PERIOD_CURRENT, 0, cn, g_cTime);
   if(h < 0 || l < 0 || t < 0) { g_cN = 0; } else { g_cN = MathMin(MathMin(h, l), t); }
   }

   int rc = 0;
   bool chartReady = true;
   if(InpChartTFLevels)
   {
      rc = RebuildTF(g_mid, g_up, g_dn, g_time_m, count, "C_",
                     InpColUp, InpColDn, InpColUp, InpColDn,
                     true, false, InpProjBars);
      if(InpDebug) PrintFormat("[KCE] RebuildTF count=%d rc=%d", count, rc);
      chartReady = (rc >= 0);
   }

   bool d1Ready = true;
   if(InpD1Levels)
   {
      int nd1 = CalcBandsOnTF(PERIOD_D1, g_mid1, g_up1, g_dn1, g_time1);
      if(nd1 >= 10)
      {
         int rd = RebuildTF(g_mid1, g_up1, g_dn1, g_time1, nd1, "D_",
                            InpColUpD1, InpColDnD1, InpColUpD1b, InpColDnD1b,
                            true, true, 0);
         d1Ready = (rd >= 0);
      }
   }

   if(InpDebug) PrintFormat("[KCE] g_cN=%d chartPivots=%d d1Ready=%d drawn=%d", g_cN, rc, d1Ready, g_drawn);
   ChartRedraw(0);
   return chartReady && d1Ready;
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   static datetime lastBar = 0;

   if(rates_total < MathMax(InpEMAPeriod, InpATRPeriod) + 2)
   {
      if(InpDebug) PrintFormat("[KCE] pocos datos: rates_total=%d < %d", rates_total, MathMax(InpEMAPeriod, InpATRPeriod) + 2);
      return prev_calculated;
   }

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   // Clamp a las barras realmente calculadas por iMA/iATR (igual que KernelCurveFVG).
   // En simbolos con historial aun sincronizando, BarsCalculated < rates_total y
   // CopyBuffer(n) devolveria < n -> el indicador saldria sin dibujar nada.
   int emaCalc = BarsCalculated(g_hEMA);
   int atrCalc = BarsCalculated(g_hATR);
   if(emaCalc <= 0 || atrCalc <= 0)
   {
      if(InpDebug) PrintFormat("[KCE] handles sin calcular: emaCalc=%d atrCalc=%d", emaCalc, atrCalc);
      return prev_calculated;
   }
   int n = MathMin(MathMin(rates_total, InpMaxBars), MathMin(emaCalc, atrCalc));
   if(n < MathMax(InpEMAPeriod, InpATRPeriod) + 2) return prev_calculated;

   // Canal estandar nativo: EMA + ATR Wilder (idem Keltner del market)
   double atr[]; ArraySetAsSeries(atr, true);
   int emaOk = CopyBuffer(g_hEMA, 0, 0, n, g_mid);
   int atrOk = CopyBuffer(g_hATR, 0, 0, n, atr);
   if(InpDebug) PrintFormat("[KCE] rates_total=%d emaCalc=%d atrCalc=%d n=%d emaCopied=%d atrCopied=%d", rates_total, emaCalc, atrCalc, n, emaOk, atrOk);
   if(emaOk < n || atrOk < n) return prev_calculated;

   // Recortar las barras mas viejas sin ATR valido (warmup de iATR). En TFs altos
   // donde n == historial completo, las primeras barras vienen como EMPTY_VALUE y
   // generarian banda infinita (up-dn = inf), rompiendo el umbral de DetectCurves.
   int minBars = MathMax(InpEMAPeriod, InpATRPeriod) + 2;
   while(n > minBars &&
         (atr[n-1] <= 0.0 || atr[n-1] >= EMPTY_VALUE || !MathIsValidNumber(atr[n-1])))
      n--;
   if(n < minBars) return prev_calculated;

   for(int i = 0; i < n; i++)
   { g_up[i] = g_mid[i] + InpATRMult*atr[i]; g_dn[i] = g_mid[i] - InpATRMult*atr[i]; }

   datetime cur = time[0];
   if(prev_calculated == 0 || cur != lastBar)
   {
      if(Rebuild(n, time)) lastBar = cur;
   }
   return rates_total;
}
//+------------------------------------------------------------------+
