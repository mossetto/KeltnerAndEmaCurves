//+------------------------------------------------------------------+
//| KeltnerAndEmasCurves.mq5                                         |
//|                                                                  |
//| Combina KernelCurveExtension + UnifiedStructureEA en UNO solo:   |
//|  - Cruce EMA (casos incrementales) + botones de ordenes.         |
//|  - Curvas Keltner: _X/_XC, paralela, conector _C, KB/KA,         |
//|    bandas al impacto BB/BM, paralelas grises y modo onlyK.       |
//|                                                                  |
//| ================= DEPENDENCIA EXTERNA (OBLIGATORIA) ============ |
//|  Requiere el indicador Keltner ADJUNTO AL GRAFICO:               |
//|      "Keltner Channels Enhanced"  (o el que use InpKeltnerName)  |
//|  >> CONFIGURARLO con: EMA Period = 50  y  ATR Period = 20 <<     |
//|  El EA NO lo calcula: lee sus buffers (0=central,1=sup,2=inf).   |
//|                                                                  |
//|  Las EMAs del cruce (iMA) son internas (no dependen de nada).    |
//|  InpD1Levels (OFF por defecto) usa el Keltner del Market via      |
//|  iCustom: NO funciona en el Strategy Tester (producto protegido).|
//| ================================================================ |
//|                                                                  |
//| Prefijo unico "KEC_".                                            |
//+------------------------------------------------------------------+
#property copyright "KeltnerAndEmasCurves"
#property version "1.00"
#include <Trade/Trade.mqh>
CTrade trade;

//============================== INPUTS ===============================
input group "Heiken Ashi"
input double alpha           = 0.33;

input group "EMAs (cruce)"
input int    InpFastPeriod   = 20;
input int    InpSlowPeriod   = 200;
input int    InpMinBars      = 20;
input color  InpColorUp      = clrLime;
input color  InpColorDown    = clrRed;
input bool   InpDefaultVisible = false;
input bool   InpShowRR       = false;

input group "Keltner (ya attachado al chart)"
input string InpKeltnerName  = "Keltner Enhanced V2.2";
input int    InpBufMid       = 0;
input int    InpBufUpper     = 1;
input int    InpBufLower     = 2;

input group "Keltner D1 (niveles con corte dinamico)"
input bool   InpD1Levels     = false;
input string InpKeltnerCustom = "Market\\Keltner Channels Enhanced";
input color  InpColUpD1      = clrAqua;
input color  InpColDnD1      = clrOrange;
input color  InpColUpD1b     = clrDeepSkyBlue;
input color  InpColDnD1b     = clrDarkOrange;
input double InpCutSize      = 0.3;
input int    InpMaxBars      = 20000;
input double InpMinCurveFrac = 0.35;
input double InpWidthMult    = 1.0;
input bool   InpUseFullWidth = true;
input bool   InpShowCurveDot = true;
input int    InpKLineWidth   = 2;

input group "Keltner chart TF"
input bool   InpChartTFLevels = true;
input int    InpProjBars     = 30;
input bool   InpShowParallel = false;
input double InpParallelPct  = 0.25;
input color  InpColUp        = clrLime;
input color  InpColDn        = clrRed;

input group "Keltner bandas al impacto / onlyK"
input bool   InpShowImpactBands = true;  // BB/BM al impactar la proyeccion
input bool   InpOnlyK           = true; // Solo mostrar BB/BM y el conector _C (oculta _X/_XC/_D/KB-KA)
input bool   InpShowBandPar      = false; // Paralelas grises a BB/BM (hacia afuera)
input double InpBandParPct        = 25;   // Separacion paralelas = % del rango BB-BM

input group "Ordenes"
input double InpRiskPct      = 0.5;
input double InpRR           = 5.0;
input double InpSLBufferPips = 2.0;
input long   InpMagic        = 20240601;
input int    InpSlippage     = 20;

//============================ DEFINES ================================
#define PRE       "KEC_"
#define PRE_EL    "KEC_EL_"
#define PRE_EB    "KEC_EB_"
#define PRE_KL    "KEC_KL_"
#define NLEVELS   6

//============================ STRUCTS ================================
struct CrossCase
{
   long     id;
   datetime tcross;
   bool     isBuy;
   color    clr;
   double   lvl[NLEVELS];
   datetime tlvl[NLEVELS];
   datetime tend[NLEVELS];
   bool     touched[NLEVELS];
   double   seg_top;
   double   ext_val;
   datetime t_ha;
   double   ha_close;
   bool     visible;
   bool     ordered;
   double   Rstep;
   bool     rr_done[NLEVELS];
   double   rr_best[NLEVELS];
};


//============================ GLOBALES ===============================
int   h_fast = INVALID_HANDLE;
int   h_slow = INVALID_HANDLE;
int   h_kelt = INVALID_HANDLE;   // Keltner del chart (TF actual)
int   h_kd1  = INVALID_HANDLE;   // Keltner D1 via iCustom

CrossCase g_cases[];

double   haOpen[], haClose[];

// OHLC del chart para fallback de toque
double   g_cHigh[], g_cLow[];
datetime g_cTime[];
int      g_cN = 0;

// Arrays Keltner (series: 0=reciente)
double   g_mid[],  g_up[],  g_dn[];   datetime g_ktime[];
double   g_mid1[], g_up1[], g_dn1[];  datetime g_ktime1[];

int      g_lastCrossIdx = -1;
bool     g_firstRun     = true;
long     g_soloId       = 0;
int      g_prevBars     = 0;
datetime g_lastBar      = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   h_fast = iMA(_Symbol, PERIOD_CURRENT, InpFastPeriod, 0, MODE_SMA, PRICE_CLOSE);
   h_slow = iMA(_Symbol, PERIOD_CURRENT, InpSlowPeriod, 0, MODE_SMA, PRICE_CLOSE);
   if(h_fast == INVALID_HANDLE || h_slow == INVALID_HANDLE)
   { Print("[USE] FALLO medias"); return INIT_FAILED; }

   h_kelt = FindKeltner();
   if(h_kelt == INVALID_HANDLE)
      Print("[USE] Keltner del chart no encontrado; reintentando en tick.");

   if(InpD1Levels)
   {
      h_kd1 = iCustom(_Symbol, PERIOD_D1, InpKeltnerCustom);
      if(h_kd1 == INVALID_HANDLE)
         PrintFormat("[USE] iCustom D1 '%s' no disponible", InpKeltnerCustom);
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   ArraySetAsSeries(g_mid,   true); ArraySetAsSeries(g_up,   true);
   ArraySetAsSeries(g_dn,    true); ArraySetAsSeries(g_ktime, true);
   ArraySetAsSeries(g_mid1,  true); ArraySetAsSeries(g_up1,  true);
   ArraySetAsSeries(g_dn1,   true); ArraySetAsSeries(g_ktime1,true);
   ArraySetAsSeries(g_cHigh, true); ArraySetAsSeries(g_cLow,  true);
   ArraySetAsSeries(g_cTime, true);

   ArrayResize(g_cases, 0);
   g_lastCrossIdx = -1;
   g_firstRun     = true;
   g_soloId       = 0;
   g_prevBars     = 0;
   g_lastBar      = 0;

   ProcessBars();
   g_lastBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   ChartRedraw();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PRE);
   if(h_fast != INVALID_HANDLE) IndicatorRelease(h_fast);
   if(h_slow != INVALID_HANDLE) IndicatorRelease(h_slow);
   if(h_kelt != INVALID_HANDLE) IndicatorRelease(h_kelt);
   if(h_kd1  != INVALID_HANDLE) IndicatorRelease(h_kd1);
}

void OnTick()
{
   datetime bt = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bt == g_lastBar) return;
   g_lastBar = bt;
   ProcessBars();
}

void OnTimer()
{
   datetime bt = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bt != g_lastBar) { g_lastBar = bt; ProcessBars(); ChartRedraw(); }
}

//+------------------------------------------------------------------+
//| Orquestador principal — se llama una vez por barra nueva          |
//+------------------------------------------------------------------+
void ProcessBars()
{
   int rt = Bars(_Symbol, PERIOD_CURRENT);
   if(rt < InpSlowPeriod + 5) return;

   // Retry Keltner handle si fallo en OnInit
   if(h_kelt == INVALID_HANDLE) h_kelt = FindKeltner();

   //--- OHLC del chart (para fallback de toque)
   g_cN = 0;
   int cn = MathMin(InpMaxBars, rt);
   if(cn >= 10)
   {
      int h = CopyHigh(_Symbol, PERIOD_CURRENT, 0, cn, g_cHigh);
      int l = CopyLow (_Symbol, PERIOD_CURRENT, 0, cn, g_cLow);
      int t = CopyTime(_Symbol, PERIOD_CURRENT, 0, cn, g_cTime);
      g_cN = MathMin(MathMin(h, l), t);
   }

   datetime time[];  double open[], high[], low[], close[];
   ArraySetAsSeries(time, false); ArraySetAsSeries(open,  false);
   ArraySetAsSeries(high, false); ArraySetAsSeries(low,   false);
   ArraySetAsSeries(close, false);
   if(CopyTime (_Symbol, PERIOD_CURRENT, 0, rt, time)  < rt) return;
   if(CopyOpen (_Symbol, PERIOD_CURRENT, 0, rt, open)  < rt) return;
   if(CopyHigh (_Symbol, PERIOD_CURRENT, 0, rt, high)  < rt) return;
   if(CopyLow  (_Symbol, PERIOD_CURRENT, 0, rt, low)   < rt) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, rt, close) < rt) return;

   //--- HA (solo logica)
   if(ArraySize(haOpen) < rt) { ArrayResize(haOpen, rt); ArrayResize(haClose, rt); }
   int startHA = (g_prevBars > 0) ? g_prevBars - 1 : 1;
   if(g_prevBars == 0) { haClose[0]=(open[0]+high[0]+low[0]+close[0])/4.0; haOpen[0]=(open[0]+close[0])/2.0; }
   for(int i = MathMax(startHA,1); i < rt; i++)
   {
      haClose[i] = (open[i]+high[i]+low[i]+close[i])/4.0;
      haOpen[i]  = alpha*((haOpen[i-1]+haClose[i-1])/2.0)+(1.0-alpha)*haOpen[i-1];
   }

   //--- Medias
   double fast_buf[], slow_buf[];
   ArraySetAsSeries(fast_buf, false); ArraySetAsSeries(slow_buf, false);
   if(CopyBuffer(h_fast,0,0,rt,fast_buf)<rt || CopyBuffer(h_slow,0,0,rt,slow_buf)<rt) return;

   //--- Cruces EMA
   int start = (g_prevBars > 1) ? g_prevBars-1 : InpSlowPeriod+1;
   if(g_lastCrossIdx < 0 || g_lastCrossIdx < start-1) g_lastCrossIdx = start;
   for(int i = start; i < rt; i++)
   {
      bool crossUp   = (fast_buf[i-1]<=slow_buf[i-1] && fast_buf[i]>slow_buf[i]);
      bool crossDown = (fast_buf[i-1]>=slow_buf[i-1] && fast_buf[i]<slow_buf[i]);
      if(crossUp || crossDown)
      {
         if(g_lastCrossIdx >= 0 && (i-g_lastCrossIdx) < InpMinBars) continue;
         if(g_lastCrossIdx >= 0 && g_lastCrossIdx < i)
            BuildCrossCase(crossUp, i, time, open, high, low, close, slow_buf, fast_buf[i], rt);
         g_lastCrossIdx = i;
      }
   }

   //--- Proyecciones EMA (corte por toque)
   UpdateProjections(time, high, low, rt);

   //--- Keltner (rebuild completo de lineas, botones estables)
   RebuildKeltner();

   RepositionButtons();
   UpdateOrderButtons();

   if(g_firstRun) g_firstRun = false;
   g_prevBars = rt;
   ChartRedraw();
}

//====================================================================
//  SECCION EMA CROSS
//====================================================================

void BuildCrossCase(bool crossUp, int i,
                    const datetime &time[], const double &open[],
                    const double &high[], const double &low[], const double &close[],
                    const double &slow_buf[], double f_now, int rt)
{
   for(int c=0;c<ArraySize(g_cases);c++) if(g_cases[c].id==(long)time[i]) return;

   color clr = crossUp ? InpColorUp : InpColorDown;

   double ext_val = crossUp ? low[g_lastCrossIdx] : high[g_lastCrossIdx];
   int    ext_idx = g_lastCrossIdx;
   for(int j=g_lastCrossIdx;j<=i;j++)
   {
      if(crossUp  && low[j]  < ext_val) { ext_val=low[j];  ext_idx=j; }
      if(!crossUp && high[j] > ext_val) { ext_val=high[j]; ext_idx=j; }
   }

   int mark_idx=-1;
   for(int j=ext_idx;j<=i;j++)
   {
      bool ok = crossUp ? (haClose[j]>slow_buf[j]) : (haClose[j]<slow_buf[j]);
      if(ok){mark_idx=j;break;}
   }
   double seg_top = (mark_idx>=0) ? haClose[mark_idx] : f_now;

   double mid  = (seg_top+ext_val)/2.0;
   double q1   = mid+(ext_val-mid)*(1.0/3.0);
   double q2   = mid+(ext_val-mid)*(2.0/3.0);
   double outv = ext_val+(ext_val-mid)*(1.0/3.0);
   double out2v= ext_val+(ext_val-mid)*(2.0/3.0);

   int n = ArraySize(g_cases);
   ArrayResize(g_cases, n+1);
   CrossCase cc;
   cc.id=((long)time[i]); cc.tcross=time[i]; cc.isBuy=crossUp; cc.clr=clr;
   cc.seg_top=seg_top; cc.ext_val=ext_val;
   cc.lvl[0]=ext_val; cc.tlvl[0]=time[ext_idx];
   cc.lvl[1]=mid;     cc.tlvl[1]=time[i];
   cc.lvl[2]=q1;      cc.tlvl[2]=time[i];
   cc.lvl[3]=q2;      cc.tlvl[3]=time[i];
   cc.lvl[4]=outv;    cc.tlvl[4]=time[i];
   cc.lvl[5]=out2v;   cc.tlvl[5]=time[i];
   cc.Rstep=MathAbs(ext_val-mid)/3.0;
   for(int k=0;k<NLEVELS;k++)
   { cc.tend[k]=time[i]; cc.touched[k]=false; cc.rr_done[k]=false; cc.rr_best[k]=cc.lvl[k]; }
   cc.t_ha    =(mark_idx>=0)?time[mark_idx]:0;
   cc.ha_close=(mark_idx>=0)?haClose[mark_idx]:0.0;
   cc.visible =InpDefaultVisible;
   cc.ordered =false;
   g_cases[n]=cc;
   CreateCaseObjects(n);
}

//+------------------------------------------------------------------+
void CreateCaseObjects(int c)
{
   string sid = IntegerToString(g_cases[c].id);
   color  clr = g_cases[c].clr;

   ECreateSegment(g_cases[c].tcross,g_cases[c].seg_top,g_cases[c].tcross,g_cases[c].ext_val,clr,PRE_EL+"SEG_"+sid);
   if(g_cases[c].t_ha!=0) ECreateHLine(g_cases[c].t_ha,g_cases[c].tcross,g_cases[c].ha_close,clr,PRE_EL+"HA_"+sid,STYLE_DASH,2);

   datetime t2=g_cases[c].tcross+(datetime)(2*PeriodSeconds());
   datetime t3=g_cases[c].tcross+(datetime)(3*PeriodSeconds());
   ECreateHLine(g_cases[c].tlvl[0],g_cases[c].tcross,g_cases[c].lvl[0],clr,PRE_EL+"B_EXT_"+sid,STYLE_SOLID,1);
   ECreateHLine(g_cases[c].tcross,t3,g_cases[c].lvl[1],clr,PRE_EL+"B_MIDC_"+sid,STYLE_SOLID,1);
   ECreateHLine(g_cases[c].tcross,t2,g_cases[c].lvl[2],clr,PRE_EL+"B_MIDA_"+sid,STYLE_SOLID,1);
   ECreateHLine(g_cases[c].tcross,t2,g_cases[c].lvl[3],clr,PRE_EL+"B_MIDB_"+sid,STYLE_SOLID,1);

   string lp[NLEVELS]={"EXT_","MIDC_","MIDA_","MIDB_","OUT_","OUT2_"};
   for(int k=0;k<NLEVELS;k++)
   {
      ENUM_LINE_STYLE sty=(k==5)?STYLE_DASH:STYLE_SOLID;
      datetime ts=(k==0)?g_cases[c].tlvl[0]:g_cases[c].tcross;
      ECreateHLine(ts,g_cases[c].tend[k],g_cases[c].lvl[k],clr,PRE_EL+lp[k]+sid,sty,1);
   }

   CreateCaseButtons(c);
   ApplyVisibility(c);
}

//+------------------------------------------------------------------+
void UpdateProjections(const datetime &time[], const double &high[], const double &low[], int rt)
{
   int total=ArraySize(g_cases); if(total==0) return;

   datetime oldest=0; bool any_pending=false;
   for(int c=0;c<total;c++) for(int k=0;k<NLEVELS;k++) if(!g_cases[c].touched[k])
   { any_pending=true; if(oldest==0||g_cases[c].tcross<oldest) oldest=g_cases[c].tcross; }

   datetime now=TimeCurrent();
   MqlRates m5[]; ArraySetAsSeries(m5,false); int copied=0;
   if(any_pending)
   {
      ENUM_TIMEFRAMES tfs[]={PERIOD_M5,PERIOD_M15,PERIOD_M30,PERIOD_H1,PERIOD_H4};
      for(int t=0;t<ArraySize(tfs);t++)
      {
         int psec=PeriodSeconds(tfs[t]); if(psec<=0) continue;
         int need=(int)((now-oldest)/psec)+20; if(need<100)need=100;
         ArraySetAsSeries(m5,false);
         copied=CopyRates(_Symbol,tfs[t],0,need,m5);
         if(copied>0) break;
      }
   }
   bool m5ok=(copied>0);
   datetime last_end = m5ok ? m5[copied-1].time : (g_cN>0?g_cTime[0]:now);

   string lp[NLEVELS]={"EXT_","MIDC_","MIDA_","MIDB_","OUT_","OUT2_"};
   for(int c=0;c<total;c++)
   {
      string sid=IntegerToString(g_cases[c].id);
      bool m5Covers=(m5ok && m5[0].time<=g_cases[c].tcross);
      for(int k=0;k<NLEVELS;k++)
      {
         double price=g_cases[c].lvl[k];
         if(!g_cases[c].touched[k])
         {
            datetime t_touch=0;
            if(m5ok && m5Covers)
               for(int b=0;b<copied;b++)
               { if(m5[b].time<=g_cases[c].tcross) continue; if(m5[b].low<=price&&price<=m5[b].high){t_touch=m5[b].time;break;} }
            if(t_touch==0)
               for(int b=0;b<rt;b++)
               { if(time[b]<=g_cases[c].tcross) continue; if(low[b]<=price&&price<=high[b]){t_touch=time[b];break;} }

            datetime ne=(t_touch!=0)?t_touch:last_end;
            if(t_touch!=0) g_cases[c].touched[k]=true;
            g_cases[c].tend[k]=ne;
            string ln=PRE_EL+lp[k]+sid;
            if(ObjectFind(0,ln)>=0) ObjectMove(0,ln,1,ne,price);
         }

         if(InpShowRR&&g_cases[c].touched[k]&&!g_cases[c].rr_done[k]&&m5ok&&m5Covers&&g_cases[c].Rstep>0.0)
         {
            double R=g_cases[c].Rstep;
            double slpx=g_cases[c].isBuy?(price-R):(price+R);
            double best=g_cases[c].rr_best[k]; bool stop=false;
            for(int b=0;b<copied;b++)
            {
               if(m5[b].time<g_cases[c].tend[k]) continue;
               if(g_cases[c].isBuy){if(m5[b].low<=slpx){stop=true;break;}}
               else                {if(m5[b].high>=slpx){stop=true;break;}}
               if(m5[b].time>g_cases[c].tend[k])
               { if(g_cases[c].isBuy){if(m5[b].high>best)best=m5[b].high;} else{if(m5[b].low<best)best=m5[b].low;} }
            }
            g_cases[c].rr_best[k]=best;
            if(stop)
            {
               double fav=g_cases[c].isBuy?(best-price):(price-best);
               int rr=(int)MathFloor(fav/R); if(rr<0)rr=0; if(rr>10)rr=10;
               g_cases[c].rr_done[k]=true;
               CreateRRText(c,k,rr);
               ApplyVisibility(c);
            }
         }
      }
   }
}

//====================================================================
//  SECCION KELTNER
//====================================================================

int FindKeltner()
{
   int winTotal=(int)ChartGetInteger(0,CHART_WINDOWS_TOTAL);
   for(int win=0;win<winTotal;win++)
   {
      int tot=ChartIndicatorsTotal(0,win);
      for(int i=0;i<tot;i++)
      {
         string nm=ChartIndicatorName(0,win,i);
         if(StringFind(nm,"KeltnerAndEmasCurves")>=0) continue;
         bool match=(InpKeltnerName!=""&&StringFind(nm,InpKeltnerName)>=0)||(StringFind(nm,"Keltner")>=0);
         if(match){int h=ChartIndicatorGet(0,win,nm);if(h!=INVALID_HANDLE)return h;}
      }
   }
   return INVALID_HANDLE;
}

int LoadKeltnerTF(int handle, double &mid[], double &up[], double &dn[], datetime &time[], ENUM_TIMEFRAMES tf)
{
   if(handle==INVALID_HANDLE) return 0;
   int calc=BarsCalculated(handle); if(calc<=0) return 0;
   int n=MathMin(InpMaxBars,MathMin(calc,Bars(_Symbol,tf))); if(n<10) return 0;
   int got=MathMin(MathMin(CopyBuffer(handle,InpBufMid,0,n,mid),CopyBuffer(handle,InpBufUpper,0,n,up)),
                   MathMin(CopyBuffer(handle,InpBufLower,0,n,dn),CopyTime(_Symbol,tf,0,n,time)));
   return (got<10)?0:got;
}

void DetectCurves(const double &mid[], const double &up[], const double &dn[], int n,
                  int &pivIdx[], bool &pivPeak[], int &confIdx[])
{
   ArrayResize(pivIdx,0); ArrayResize(pivPeak,0); ArrayResize(confIdx,0);
   int dir=0, extIdx=n-1; double extVal=mid[n-1];
   for(int i=n-2;i>=0;i--)
   {
      double v=mid[i];
      double thr=InpMinCurveFrac*MathMax(up[extIdx]-dn[extIdx],_Point);
      if(dir>=0)
      {
         if(v>=extVal){extVal=v;extIdx=i;}
         else if(extVal-v>=thr){int m=ArraySize(pivIdx);ArrayResize(pivIdx,m+1);ArrayResize(pivPeak,m+1);ArrayResize(confIdx,m+1);pivIdx[m]=extIdx;pivPeak[m]=true;confIdx[m]=i;dir=-1;extVal=v;extIdx=i;}
      }
      else
      {
         if(v<=extVal){extVal=v;extIdx=i;}
         else if(v-extVal>=thr){int m=ArraySize(pivIdx);ArrayResize(pivIdx,m+1);ArrayResize(pivPeak,m+1);ArrayResize(confIdx,m+1);pivIdx[m]=extIdx;pivPeak[m]=false;confIdx[m]=i;dir=+1;extVal=v;extIdx=i;}
      }
   }
}

datetime FindTouchTime(double level, datetime fromTime, bool levelAbove)
{
   // 1) Intentar con datos del chart TF (g_cHigh/g_cLow son series: 0=newest, N-1=oldest)
   bool chartCovers = (g_cN > 0 && g_cTime[g_cN-1] <= fromTime);
   if(g_cN > 0)
   {
      for(int i=g_cN-1;i>=0;i--)
      {
         if(g_cTime[i]<=fromTime) continue;
         if(levelAbove && g_cHigh[i]>=level) return g_cTime[i];
         if(!levelAbove && g_cLow[i] <=level) return g_cTime[i];
      }
      if(chartCovers) return 0;  // chart cubre el periodo y no hay toque
   }

   // 2) Chart TF no cubre el periodo -> escalar a TFs superiores
   ENUM_TIMEFRAMES tfs[] = {PERIOD_H4, PERIOD_D1, PERIOD_W1, PERIOD_MN1};
   for(int t=0;t<ArraySize(tfs);t++)
   {
      int psec = PeriodSeconds(tfs[t]);
      if(psec <= PeriodSeconds()) continue;  // solo TFs mayores al actual
      int need = (int)((TimeCurrent()-fromTime)/psec) + 10;
      if(need < 50) need = 50;
      double hi[], lo[]; datetime tm[];
      ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true); ArraySetAsSeries(tm,true);
      int got = MathMin(CopyHigh(_Symbol,tfs[t],0,need,hi),
                MathMin(CopyLow (_Symbol,tfs[t],0,need,lo),
                        CopyTime(_Symbol,tfs[t],0,need,tm)));
      if(got<=0) continue;
      bool covers = (tm[got-1] <= fromTime);
      for(int i=got-1;i>=0;i--)
      {
         if(tm[i]<=fromTime) continue;
         if(levelAbove && hi[i]>=level) return tm[i];
         if(!levelAbove && lo[i] <=level) return tm[i];
      }
      if(covers) return 0;  // este TF cubre el periodo y no hay toque
   }
   return 0;
}

void KDrawLine(string name, datetime tA, datetime tB, double lv, color clr, int width, ENUM_LINE_STYLE sty)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TREND,0,tA,lv,tB,lv);
   else{ObjectMove(0,name,0,tA,lv);ObjectMove(0,name,1,tB,lv);}
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_STYLE,sty);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void KDrawCut(string name, datetime t, double lv, double half, color clr)
{
   if(half<=0) return;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TREND,0,t,lv-half,t,lv+half);
   else{ObjectMove(0,name,0,t,lv-half);ObjectMove(0,name,1,t,lv+half);}
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

// Banda al impacto (punteada) desde el pivote hasta el toque post-conf.
datetime DrawBandLine(string name, datetime tA, double level, datetime fromTime, bool touchHigh, color clr)
{
   if(g_cN<=0) return 0;
   if(fromTime<=0) fromTime=tA;
   datetime tt=FindTouchTime(level,fromTime,touchHigh);
   datetime tB=(tt>0)?tt:g_cTime[0];
   KDrawLine(name,tA,tB,level,clr,1,STYLE_DOT);
   return tB;
}
// Paralela gris a una BB/BM (mismo largo).
void DrawGrayPar(string name, datetime tA, double level, datetime tB)
{
   KDrawLine(name,tA,tB,level,clrGray,1,STYLE_DOT);
}

// Dibuja una curva Keltner (lineas + punto + cortes)
void DrawKCurve(string tag, int ci, datetime tConf,
                double bandRef, double level, double level2, double width,
                color clr, color clrP, int n, const datetime &time[],
                bool cutAtTouch, bool showParallel, int projBars)
{
   datetime tA=time[ci];
   datetime tB, tB2;

   bool levelAbove=(level>=bandRef);

   if(cutAtTouch)
   {
      datetime tt=FindTouchTime(level,tA,levelAbove);
      tB=(tt>0)?tt:(g_cN>0?g_cTime[0]:tA);
      datetime tt2=FindTouchTime(level2,tA,levelAbove);
      tB2=(tt2>0)?tt2:(g_cN>0?g_cTime[0]:tA);
   }
   else
   {
      int ri=MathMax(0,ci-projBars);
      tB=time[ri]; tB2=tB;
   }

   if(!InpOnlyK)
   {
      KDrawLine(PRE_KL+tag+"_X",  tA,tB,  level,  clr,  InpKLineWidth,STYLE_SOLID);
      if(showParallel)
         KDrawLine(PRE_KL+tag+"_X2", tA,tB2, level2, clrP, InpKLineWidth,STYLE_SOLID);

      // Cortes de confirmacion
      double cutH=width*InpCutSize*0.5;
      if(tConf>0 && cutH>0)
      {
         KDrawCut(PRE_KL+tag+"_XC",  tConf, level,  cutH, clr);
         if(showParallel)
            KDrawCut(PRE_KL+tag+"_X2C", tConf, level2, cutH, clrP);
      }
   }

   // Conector
   string cn=PRE_KL+tag+"_C";
   if(ObjectFind(0,cn)<0) ObjectCreate(0,cn,OBJ_TREND,0,tA,bandRef,tA,level);
   else{ObjectMove(0,cn,0,tA,bandRef);ObjectMove(0,cn,1,tA,level);}
   ObjectSetInteger(0,cn,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,cn,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,cn,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,cn,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,cn,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,cn,OBJPROP_BACK,false);
   ObjectSetInteger(0,cn,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,cn,OBJPROP_HIDDEN,true);

   // Etiqueta KB (pico) / KA (valle) en el angulo C-X
   if(!InpOnlyK)
   {
      string kl=PRE_KL+tag+"_KL";
      string ktxt=levelAbove?"KA":"KB";
      int    kanch=levelAbove?ANCHOR_LEFT_UPPER:ANCHOR_LEFT_LOWER;
      datetime tk=tA+(datetime)PeriodSeconds();
      if(ObjectFind(0,kl)<0) ObjectCreate(0,kl,OBJ_TEXT,0,tk,level);
      else ObjectMove(0,kl,0,tk,level);
      ObjectSetString (0,kl,OBJPROP_TEXT,ktxt);
      ObjectSetString (0,kl,OBJPROP_FONT,"Arial Bold");
      ObjectSetInteger(0,kl,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,kl,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,kl,OBJPROP_ANCHOR,kanch);
      ObjectSetInteger(0,kl,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,kl,OBJPROP_HIDDEN,true);
   }

   // Punto de curva
   if(InpShowCurveDot && !InpOnlyK)
   {
      string dt=PRE_KL+tag+"_D";
      if(ObjectFind(0,dt)<0) ObjectCreate(0,dt,OBJ_ARROW,0,tA,bandRef);
      else ObjectMove(0,dt,0,tA,bandRef);
      ObjectSetInteger(0,dt,OBJPROP_ARROWCODE,159);
      ObjectSetInteger(0,dt,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,dt,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,dt,OBJPROP_ANCHOR,ANCHOR_CENTER);
      ObjectSetInteger(0,dt,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,dt,OBJPROP_HIDDEN,true);
   }
}

void DrawKSource(int handle, double &mid[], double &up[], double &dn[], datetime &time[],
                 ENUM_TIMEFRAMES tf, bool cutAtTouch, bool x1Parallel,
                 color colUp, color colDn, color colUpP, color colDnP,
                 string srcTag, int projBars)
{
   int n=LoadKeltnerTF(handle,mid,up,dn,time,tf);
   if(n<=0) return;
   int piv[]; bool peak[]; int conf[];
   DetectCurves(mid,up,dn,n,piv,peak,conf);
   for(int p=ArraySize(piv)-1;p>=0;p--)
   {
      int ci=piv[p]; bool pk=peak[p];
      double w=(InpUseFullWidth?(up[ci]-dn[ci]):(up[ci]-mid[ci]))*InpWidthMult;
      if(w<=0) continue;
      double bandRef=pk?dn[ci]:up[ci];
      double lv     =pk?(bandRef-w):(bandRef+w);
      double lv2    =pk?(lv-w):(lv+w);
      color  clr    =pk?colDn:colUp;
      color  clrP   =pk?colDnP:colUpP;
      datetime tConf=(conf[p]>=0&&conf[p]<n)?time[conf[p]]:(datetime)0;
      string tag=srcTag+(pk?"P_":"V_")+IntegerToString(ci);

      DrawKCurve(tag,ci,tConf,bandRef,lv,lv2,w,clr,clrP,n,time,
                 cutAtTouch,x1Parallel||InpShowParallel,projBars);

      // --- Bandas al impacto BB/BM (+ paralelas grises) ---
      if(InpShowImpactBands)
      {
         bool     mainAbove = (lv >= bandRef);
         datetime impFrom   = (tConf > 0) ? tConf : time[ci];
         datetime impact    = FindTouchTime(lv, impFrom, mainAbove);
         if(impact > 0)
         {
            double bBand = pk ? up[ci] : dn[ci];
            double bMid  = mid[ci];
            bool   tHigh = pk;
            datetime eBB = DrawBandLine(PRE_KL+tag+"_BB", time[ci], bBand, tConf, tHigh, clr);
            datetime eBM = DrawBandLine(PRE_KL+tag+"_BM", time[ci], bMid,  tConf, tHigh, clr);
            if(InpShowBandPar)
            {
               double off = MathAbs(bBand - bMid) * (InpBandParPct/100.0);
               double dir = pk ? 1.0 : -1.0;
               DrawGrayPar(PRE_KL+tag+"_BBP", time[ci], bBand + dir*off, eBB);
               DrawGrayPar(PRE_KL+tag+"_BMP", time[ci], bMid  + dir*off, eBM);
            }
         }
      }
   }
}

void RebuildKeltner()
{
   ObjectsDeleteAll(0, PRE_KL);

   if(InpChartTFLevels && h_kelt!=INVALID_HANDLE)
      DrawKSource(h_kelt,g_mid,g_up,g_dn,g_ktime,(ENUM_TIMEFRAMES)_Period,
                  true,false,InpColUp,InpColDn,InpColUp,InpColDn,"C_",InpProjBars);   // dinamico (corte al toque)

   if(InpD1Levels)
   {
      if(h_kd1==INVALID_HANDLE) h_kd1=iCustom(_Symbol,PERIOD_D1,InpKeltnerCustom);
      if(h_kd1!=INVALID_HANDLE)
         DrawKSource(h_kd1,g_mid1,g_up1,g_dn1,g_ktime1,PERIOD_D1,
                     true,true,InpColUpD1,InpColDnD1,InpColUpD1b,InpColDnD1b,"D_",0);
   }
}

//====================================================================
//  BOTONES Y VISIBILIDAD
//====================================================================

void MakeButton(string name, string text, color bg)
{
   if(ObjectFind(0,name)>=0) return;
   ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,26); ObjectSetInteger(0,name,OBJPROP_YSIZE,20);
   ObjectSetString (0,name,OBJPROP_TEXT,text);
   ObjectSetString (0,name,OBJPROP_FONT,"Arial Bold");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,10);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrBlack);
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,100);
}

void CreateCaseButtons(int c)
{
   string id=IntegerToString(g_cases[c].id);
   MakeButton(PRE_EB+"BTN_"+id,  g_cases[c].visible?"-":"+", g_cases[c].clr);
   MakeButton(PRE_EB+"SOLO_"+id, "S", g_cases[c].clr);
   MakeButton(PRE_EB+"ORD_"+id,  "$", clrPurple);
}


void AppendName(string &arr[], string nm){int n=ArraySize(arr);ArrayResize(arr,n+1);arr[n]=nm;}

void ApplyVisibility(int c)
{
   string sid=IntegerToString(g_cases[c].id);
   bool baseShown=(g_soloId==0||g_cases[c].id==g_soloId);
   bool projShown=baseShown&&g_cases[c].visible;

   string bnames[];
   AppendName(bnames,PRE_EL+"B_EXT_"+sid);  AppendName(bnames,PRE_EL+"B_MIDC_"+sid);
   AppendName(bnames,PRE_EL+"B_MIDA_"+sid); AppendName(bnames,PRE_EL+"B_MIDB_"+sid);
   AppendName(bnames,PRE_EL+"SEG_"+sid);
   if(g_cases[c].t_ha!=0) AppendName(bnames,PRE_EL+"HA_"+sid);
   int tfb=baseShown?OBJ_ALL_PERIODS:OBJ_NO_PERIODS;
   for(int n=0;n<ArraySize(bnames);n++) if(ObjectFind(0,bnames[n])>=0) ObjectSetInteger(0,bnames[n],OBJPROP_TIMEFRAMES,tfb);

   string pnames[];
   string lp[NLEVELS]={"EXT_","MIDC_","MIDA_","MIDB_","OUT_","OUT2_"};
   for(int k=0;k<NLEVELS;k++){AppendName(pnames,PRE_EL+lp[k]+sid);AppendName(pnames,PRE_EL+"RR_"+lp[k]+sid);}
   int tfp=projShown?OBJ_ALL_PERIODS:OBJ_NO_PERIODS;
   for(int n=0;n<ArraySize(pnames);n++) if(ObjectFind(0,pnames[n])>=0) ObjectSetInteger(0,pnames[n],OBJPROP_TIMEFRAMES,tfp);

   int tfbtn=baseShown?OBJ_ALL_PERIODS:OBJ_NO_PERIODS;
   string bn=PRE_EB+"BTN_"+sid;
   if(ObjectFind(0,bn)>=0){ObjectSetString(0,bn,OBJPROP_TEXT,g_cases[c].visible?"-":"+");ObjectSetInteger(0,bn,OBJPROP_TIMEFRAMES,tfbtn);}
   string sn=PRE_EB+"SOLO_"+sid;
   if(ObjectFind(0,sn)>=0){ObjectSetInteger(0,sn,OBJPROP_BGCOLOR,(g_cases[c].id==g_soloId)?clrWhite:g_cases[c].clr);ObjectSetInteger(0,sn,OBJPROP_TIMEFRAMES,tfbtn);}
   string on=PRE_EB+"ORD_"+sid;
   if(ObjectFind(0,on)>=0){ObjectSetInteger(0,on,OBJPROP_TIMEFRAMES,tfbtn);SetEOrderButtonState(c);}
}

void ApplyAllVisibility(){for(int c=0;c<ArraySize(g_cases);c++) ApplyVisibility(c);}

void RepositionButtons()
{
   long cid=0; int sub=0,x=0,y=0;

   // Botones de casos EMA
   for(int c=0;c<ArraySize(g_cases);c++)
   {
      string id=IntegerToString(g_cases[c].id);
      if(ObjectFind(0,PRE_EB+"BTN_"+id)<0) continue;
      if(ChartTimePriceToXY(cid,sub,g_cases[c].tcross,g_cases[c].ext_val,x,y))
      {
         int by=g_cases[c].isBuy?(y-22):(y+2);
         int bx=x-29;
         ObjectSetInteger(0,PRE_EB+"BTN_"+id, OBJPROP_XDISTANCE,bx);
         ObjectSetInteger(0,PRE_EB+"BTN_"+id, OBJPROP_YDISTANCE,by);
         ObjectSetInteger(0,PRE_EB+"SOLO_"+id,OBJPROP_XDISTANCE,bx-28);
         ObjectSetInteger(0,PRE_EB+"SOLO_"+id,OBJPROP_YDISTANCE,by);
         ObjectSetInteger(0,PRE_EB+"ORD_"+id, OBJPROP_XDISTANCE,bx-56);
         ObjectSetInteger(0,PRE_EB+"ORD_"+id, OBJPROP_YDISTANCE,by);
      }
   }

}

void CreateRRText(int c, int k, int rr)
{
   string lp[NLEVELS]={"EXT_","MIDC_","MIDA_","MIDB_","OUT_","OUT2_"};
   string name=PRE_EL+"RR_"+lp[k]+IntegerToString(g_cases[c].id);
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   datetime ta=g_cases[c].tend[k]-(datetime)(5*300);
   string txt=(rr>0)?(IntegerToString(rr)+":1"):"SL";
   color  tc =(rr>0)?clrLime:clrRed;
   ObjectCreate(0,name,OBJ_TEXT,0,ta,g_cases[c].lvl[k]);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_RIGHT_LOWER);
   ObjectSetString (0,name,OBJPROP_TEXT,txt);
   ObjectSetString (0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_COLOR,tc);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,g_cases[c].visible?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
}

//====================================================================
//  ORDENES
//====================================================================

double PipSize(){double p=_Point;if(_Digits==3||_Digits==5)p=10.0*_Point;return p;}

double CalcLot(double slDist)
{
   if(slDist<=0) return 0.0;
   double risk=AccountInfoDouble(ACCOUNT_BALANCE)*InpRiskPct/100.0;
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tv<=0||ts<=0) return 0.0;
   double lpp=(slDist/ts)*tv; if(lpp<=0) return 0.0;
   double lots=risk/lpp;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double vmax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step>0) lots=MathFloor(lots/step)*step;
   if(lots<vmin)lots=vmin; if(lots>vmax)lots=vmax;
   return lots;
}

ENUM_ORDER_TYPE PendingType(bool isBuy, double entry, string &nm)
{
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(isBuy){if(entry<=ask){nm="BUY LIMIT";return ORDER_TYPE_BUY_LIMIT;}nm="BUY STOP";return ORDER_TYPE_BUY_STOP;}
   else     {if(entry>=bid){nm="SELL LIMIT";return ORDER_TYPE_SELL_LIMIT;}nm="SELL STOP";return ORDER_TYPE_SELL_STOP;}
}

bool OrderExistsAt(double price)
{
   double tol=_Point/2.0;
   for(int i=PositionsTotal()-1;i>=0;i--){ulong tk=PositionGetTicket(i);if(!tk)continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;if(MathAbs(PositionGetDouble(POSITION_PRICE_OPEN)-price)<=tol)return true;}
   for(int i=OrdersTotal()-1;i>=0;i--){ulong tk=OrderGetTicket(i);if(!tk)continue;if(OrderGetString(ORDER_SYMBOL)!=_Symbol)continue;if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN)-price)<=tol)return true;}
   return false;
}

void SetEOrderButtonState(int c)
{
   string on=PRE_EB+"ORD_"+IntegerToString(g_cases[c].id);
   if(ObjectFind(0,on)<0) return;
   bool ok=g_cases[c].ordered||(OrderExistsAt(NormalizeDouble(g_cases[c].lvl[0],_Digits))&&OrderExistsAt(NormalizeDouble(g_cases[c].lvl[3],_Digits)));
   ObjectSetInteger(0,on,OBJPROP_BGCOLOR,ok?clrDimGray:clrPurple);
   ObjectSetString (0,on,OBJPROP_TEXT,   ok?"OK":"$");
}


void UpdateOrderButtons()
{
   for(int c=0;c<ArraySize(g_cases);c++) SetEOrderButtonState(c);
}

// --- Ordenes caso EMA (igual que v4_EA: EXT + MIDB) ---
void PlaceCrossOrders(int c)
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)||!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {MessageBox("Trading no permitido.","USE EA",MB_OK|MB_ICONWARNING);return;}
   bool isBuy=g_cases[c].isBuy; double pip=PipSize(); int dg=_Digits;
   double e_ext=NormalizeDouble(g_cases[c].lvl[0],dg);
   double e_mid=NormalizeDouble(g_cases[c].lvl[3],dg);
   double sl_ext=NormalizeDouble(g_cases[c].lvl[4],dg);
   double sl_mid=NormalizeDouble(isBuy?(g_cases[c].ext_val-InpSLBufferPips*pip):(g_cases[c].ext_val+InpSLBufferPips*pip),dg);
   double tp_ext=NormalizeDouble(isBuy?(e_ext+InpRR*(e_ext-sl_ext)):(e_ext-InpRR*(sl_ext-e_ext)),dg);
   double tp_mid=NormalizeDouble(isBuy?(e_mid+InpRR*(e_mid-sl_mid)):(e_mid-InpRR*(sl_mid-e_mid)),dg);
   bool extEx=OrderExistsAt(e_ext), midEx=OrderExistsAt(e_mid);
   if(extEx&&midEx){g_cases[c].ordered=true;SetEOrderButtonState(c);return;}
   double lot_ext=!extEx?CalcLot(MathAbs(e_ext-sl_ext)):0;
   double lot_mid=!midEx?CalcLot(MathAbs(e_mid-sl_mid)):0;
   string nm1,nm2;
   ENUM_ORDER_TYPE ot1=PendingType(isBuy,e_ext,nm1);
   ENUM_ORDER_TYPE ot2=PendingType(isBuy,e_mid,nm2);
   string body="EXT:  "+nm1+" @ "+DoubleToString(e_ext,dg)+"  SL "+DoubleToString(sl_ext,dg)+"  TP "+DoubleToString(tp_ext,dg)+"  lot "+DoubleToString(lot_ext,2)+"\n"
              +"MIDB: "+nm2+" @ "+DoubleToString(e_mid,dg)+"  SL "+DoubleToString(sl_mid,dg)+"  TP "+DoubleToString(tp_mid,dg)+"  lot "+DoubleToString(lot_mid,2)+"\n"
              +"\nRiesgo "+DoubleToString(InpRiskPct,2)+"% x orden. Confirmar?";
   if(MessageBox(body,"Ordenes EMA",MB_OKCANCEL|MB_ICONQUESTION)!=IDOK) return;
   if(!extEx) trade.OrderOpen(_Symbol,ot1,lot_ext,0,e_ext,sl_ext,tp_ext,ORDER_TIME_GTC,0,"USE_EXT "+IntegerToString(g_cases[c].id));
   if(!midEx) trade.OrderOpen(_Symbol,ot2,lot_mid,0,e_mid,sl_mid,tp_mid,ORDER_TIME_GTC,0,"USE_MIDB "+IntegerToString(g_cases[c].id));
   if(OrderExistsAt(e_ext)&&OrderExistsAt(e_mid)) g_cases[c].ordered=true;
   SetEOrderButtonState(c); ChartRedraw();
}


//====================================================================
//  EVENTOS DE CHART
//====================================================================
void OnChartEvent(const int id, const long &lp, const double &dp, const string &sp)
{
   if(id==CHARTEVENT_OBJECT_CLICK)
   {
      // --- Click en linea de proyeccion EMA = toggle solo de ese caso ---
      if(StringFind(sp, PRE_EL) == 0)
      {
         string lp2[NLEVELS] = {"EXT_","MIDC_","MIDA_","MIDB_","OUT_","OUT2_"};
         string sid = "";
         for(int k=0;k<NLEVELS;k++)
         {
            string pat = PRE_EL + lp2[k];
            if(StringFind(sp, pat) == 0) { sid = StringSubstr(sp, StringLen(pat)); break; }
         }
         if(sid != "")
            for(int c=0;c<ArraySize(g_cases);c++)
               if(IntegerToString(g_cases[c].id) == sid)
               {
                  g_soloId = (g_soloId == g_cases[c].id) ? 0 : g_cases[c].id;
                  ApplyAllVisibility();
                  ChartRedraw();
                  break;
               }
         return;
      }
      // --- Botones EMA: toggle (+/-) ---
      if(StringFind(sp,PRE_EB+"BTN_")==0)
      {
         string sid=StringSubstr(sp,StringLen(PRE_EB+"BTN_"));
         for(int c=0;c<ArraySize(g_cases);c++) if(IntegerToString(g_cases[c].id)==sid)
         {g_cases[c].visible=!g_cases[c].visible;ApplyVisibility(c);ObjectSetInteger(0,sp,OBJPROP_STATE,false);ChartRedraw();break;}
         return;
      }
      // --- Botones EMA: solo (S) ---
      if(StringFind(sp,PRE_EB+"SOLO_")==0)
      {
         string sid=StringSubstr(sp,StringLen(PRE_EB+"SOLO_"));
         for(int c=0;c<ArraySize(g_cases);c++) if(IntegerToString(g_cases[c].id)==sid)
         {g_soloId=(g_soloId==g_cases[c].id)?0:g_cases[c].id;ApplyAllVisibility();ObjectSetInteger(0,sp,OBJPROP_STATE,false);ChartRedraw();break;}
         return;
      }
      // --- Botones EMA: ordenes ($) ---
      if(StringFind(sp,PRE_EB+"ORD_")==0)
      {
         string sid=StringSubstr(sp,StringLen(PRE_EB+"ORD_"));
         for(int c=0;c<ArraySize(g_cases);c++) if(IntegerToString(g_cases[c].id)==sid)
         {PlaceCrossOrders(c);ObjectSetInteger(0,sp,OBJPROP_STATE,false);break;}
         return;
      }
   }
   else if(id==CHARTEVENT_CHART_CHANGE)
   { RepositionButtons(); ChartRedraw(); }
}

//====================================================================
//  HELPERS
//====================================================================
void ECreateHLine(datetime t1, datetime t2, double price, color clr, string name, ENUM_LINE_STYLE sty=STYLE_SOLID, int w=2)
{
   if(ObjectFind(0,name)>=0) return;
   ObjectCreate(0,name,OBJ_TREND,0,t1,price,t2,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);  ObjectSetInteger(0,name,OBJPROP_STYLE,sty);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,w);     ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false); ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
}

void ECreateSegment(datetime dt1, double p1, datetime dt2, double p2, color clr, string name)
{
   if(ObjectFind(0,name)>=0) return;
   ObjectCreate(0,name,OBJ_TREND,0,dt1,p1,dt2,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);  ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);     ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false); ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
}
//+------------------------------------------------------------------+
