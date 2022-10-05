* create crosswalk between advan foot traffic data store_id and sod branch id
local fname an_advan_bank_foottraffic

******************************* SYNOPSIS ***************************************
/* 
Purpose: Analyze the cleaned weekly foot traffic data of 82 banks from Advan

Author: Zirui Song
Date Created: Jul 21st, 2022
Date Modified: Oct 5th, 2022

*/

/**************
	Basic Set-up
	***************/
	clear all
	set more off, permanently
	capture log close
	
	set scheme s2color
	
	* Set local directory
	* notice that repodir path for Mac/Windows might differ
	global repodir = "/Users/zsong98/Dropbox (Chicago Booth)/Bank Foot Traffic"
	global logdir = "$repodir/code/LogFiles"
	global datadir = "$repodir/data"
	global figdir = "$repodir/output/figures/zs"
	global tabdir = "$repodir/output/tables/zs"
	
	* Start plain text log file with same name
	log using "$logdir/`fname'.txt", replace text

/**************
	Read Data
	***************/
	
*** prepare/clean SOD data due to missing uninumbr for some obs (not important, all before year 2011) 
	use "$datadir/source data/SOD/sodupdate2021", clear
	drop if uninumbr == .
	tempfile crosswalk_sod
	save `crosswalk_sod'
	
***	merge with the crosswalk to SOD 
	* prepare the crosswalk between uninumbr and id_store
	use "$datadir/source data/advan_sod_crosswalk", clear
		* drop duplicates regarding id_store for now
		duplicates drop id_store, force // 90 obs deleted for now
		tempfile crosswalk 
		save `crosswalk'

	use "$datadir/cleaned data/weekly_advan_traffic_updated20221004", clear
	* inspect possible duplicates from data source
	gduplicates tag id_store year week, gen(dup)
	gsort id_store year week 
	duplicates drop id_store year week, force
	drop dup
	* merge with crosswalk to get uninumbr from sod for future merges 
	fmerge m:1 id_store using "`crosswalk'"
	keep if _merge == 3
	drop _merge
	save "$datadir/cleaned data/weekly_advan_traffic_mergedbanks_updated20221004", replace
	
/**************
	Prediction Model for Advan
	***************/	
	use "$datadir/cleaned data/weekly_advan_traffic_mergedbanks", clear
*** generate annual average foot traffic for each id_store (use 6/30 as the date (i.e., week 26) for annual split)
*** since data only starts from week 35/36 of 2015, use the weeks in 2015 and first 26 weeks in 2016 as year 1, and 2022 data ends with week 27 ()
	gen ayear = 2016 if year == 2015 | (year == 2016 & week <= 26)
	foreach y of numlist 2016/2021 {
		local yearplus1 = `y' + 1
		replace ayear = `yearplus1' if (year == `y' & week > 26) | (year == `yearplus1' & week <= 26)
	}
	* deal with 2022 week 27 situation (drop for now, as it belongs to the data in next year)
	drop if year == 2022 & week > 26
	* this is to match SOD's June 30th report of total assets/deposits, etc.
	
*** collapse to get annual average of traffic 
	collapse (mean) devices* dwelled_* (first) uninumbr, by(ayear id_store)
	rename ayear year
	* as SOD haven't updated to 2022, drop those obs
	drop if year == 2022
	
*** merge with SOD data 
	fmerge 1:1 uninumbr year using "`crosswalk_sod'"
		drop if _merge == 2
/*
    Result                           # of obs.
    -----------------------------------------
    not matched                     2,128,127
        from master                    12,371  (_merge==1)
        from using                  2,115,756  (_merge==2)

    matched                           172,364  (_merge==3)
    -----------------------------------------
	manually check the unmatched 12,371 obs from master show that most unmatched
	observations are in 2019-2021, due to closing of bank branches probably
	* this is somewhat reflected in the large amount of 0s for "dwelled_store" variable,
	which records the number of devices dwelling more than 5 minutes at the store 
*/
	drop if _merge == 1
	drop _merge 
*** simple linear regression models 
	
	* generate traffic (according to advan definition, devices_plot/devices)
	foreach x in _store _plot _store_or_plot {
		gen traffic`x' = devices`x' / devices
	}
	* generate annual change in raw foot traffic
	foreach var of varlist devices_store devices_plot devices_store_or_plot {
		bysort id_store (year): gen delta_`var' = (`var'[_n] - `var'[_n-1]) / `var'[_n-1]
		bysort id_store (year): gen logdiff_`var' = ln(`var'[_n]) - ln(`var'[_n-1])
	}
	* generate annual change in traffic as defined above
	foreach var of varlist traffic_store traffic_plot traffic_store_or_plot {
		bysort id_store (year): gen delta_`var' = (`var'[_n] - `var'[_n-1]) / `var'[_n-1]
		bysort id_store (year): gen logdiff_`var' = ln(`var'[_n]) - ln(`var'[_n-1])
	}
	
	* simple linear regression models based on raw foot traffic 
	
	* generate log deposits and log-diff deposits 
	gen logdepsumbr = ln(depsumbr)
	bysort id_store (year): gen deltadepsumbr = (depsumbr[_n] - depsumbr[_n-1]) / depsumbr[_n-1]
	bysort id_store (year): gen logdiffdepsumbr = logdepsumbr[_n] - logdepsumbr[_n-1]
	
	// create winsorized depsumbr variables 
	winsor2 depsumbr, cuts(1 99)
	gen logdepsumbr_w = ln(depsumbr_w)
	bysort id_store (year): gen deltadepsumbr_w = (depsumbr_w[_n] - depsumbr_w[_n-1]) / depsumbr_w[_n-1]
	bysort id_store (year): gen logdiffdepsumbr_w = logdepsumbr_w[_n] - logdepsumbr_w[_n-1]	
	
	save "$datadir/temp_annual_dep_traffic", replace
	use "$datadir/temp_annual_dep_traffic", clear
	
	* output regression tables with period-on-period percentage change of traffic and deposits
foreach y of varlist depsumbr logdepsumbr deltadepsumbr depsumbr_w logdepsumbr_w deltadepsumbr_w {
	foreach var of varlist delta_* {
		if "`var'" == "delta_devices_store" {
			reghdfe `y' `var', absorb(year id_store) 
			outreg2 using "$tabdir/`y'_traffic_prediction_model.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Year FE, Yes)	
		}
		else {
			reghdfe `y' `var', absorb(year id_store) 
			outreg2 using "$tabdir/`y'_traffic_prediction_model.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Year FE, Yes)
		}
	}
	* add clustering by state
	foreach var of varlist delta_* {
		if "`var'" == "delta_devices_store" {
			reghdfe `y' `var', absorb(year id_store) vce(cl stnumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_clst.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at state level)	
		}
		else {
			reghdfe `y' `var', absorb(year id_store) vce(cl stnumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_clst.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at state level)
		}
	}
	* add clustering by county
	foreach var of varlist delta_* {
		if "`var'" == "delta_devices_store" {
			reghdfe `y' `var', absorb(year id_store) vce(cl cntynumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_clcnty.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at county level)	
		}
		else {
			reghdfe `y' `var', absorb(year id_store) vce(cl cntynumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_clcnty.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at county level)
		}
	}
	* add clustering by zip 
	foreach var of varlist delta_* {
		if "`var'" == "delta_devices_store" {
			reghdfe `y' `var', absorb(year id_store) vce(cl zipbr)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_clzip.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at zip level)	
		}
		else {
			reghdfe `y' `var', absorb(year id_store) vce(cl zipbr)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_clzip.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at zip level)
		}
	}
}
	
* output regression tables with log-diff of traffic and deposits

foreach y of varlist logdiffdepsumbr logdiffdepsumbr_w {
	foreach var of varlist logdiff_* {
		if "`var'" == "logdiff_devices_store" {
			reghdfe `y' `var', absorb(year id_store) 
			outreg2 using "$tabdir/`y'_traffic_prediction_model.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Year FE, Yes)	
		}
		else {
			reghdfe `y' `var', absorb(year id_store) 
			outreg2 using "$tabdir/`y'_traffic_prediction_model.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Year FE, Yes)
		}
	}
	* add clustering by state
	foreach var of varlist logdiff_* {
		if "`var'" == "logdiff_devices_store" {
			reghdfe `y' `var', absorb(year id_store) vce(cl stnumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_clst.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at state level)	
		}
		else {
			reghdfe `y' `var', absorb(year id_store) vce(cl stnumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_clst.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(2) append ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at state level)
		}
	}
	* add clustering by county
	foreach var of varlist logdiff_* {
		if "`var'" == "logdiff_devices_store" {
			reghdfe `y' `var', absorb(year id_store) vce(cl cntynumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_clcnty.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at county level)	
		}
		else {
			reghdfe `y' `var', absorb(year id_store) vce(cl cntynumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_clcnty.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at county level)
		}
	}
	* add clustering by zip 
	foreach var of varlist logdiff_* {
		if "`var'" == "logdiff_devices_store" {
			reghdfe `y' `var', absorb(year id_store) vce(cl zipbr)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_clzip.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at zip level)	
		}
		else {
			reghdfe `y' `var', absorb(year id_store) vce(cl zipbr)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_clzip.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at zip level)
		}
	}
}
	
/**************
	Event Study (DiD) w.r.t. Wells Fargo Scandal
	***************/	
	
use "$datadir/cleaned data/weekly_advan_traffic_mergedbanks", clear

*** generate a week id to set panel data 
egen id_week = group(year week)
xtset id_store id_week

*** Wells Fargo Scandal data (end of the week of 2018)
gen treated = 1 if strpos(bank_name, "wells fargo") != 0 
replace treated = 0 if treated >= .

gen post = 1 if year > 2016 | (year == 2016 & week > 38)
replace post = 0 if post >= .
gen treatedxpost = treated*post
replace treatedxpost = 0 if treatedxpost >=.

*** generate wells fargo scandal week
* generate the scandal week for Wells Fargo
gen event = 1 if year == 2016 & week == 38 & treated == 1
replace event = 0 if event >=.
* fill the scandal week for Wells Fargo for all wells fargo banks
gen event_week_w = id_week*event 
egen event_week = max(event_week_w)
drop event_week_w

*** regression tables 
	egen zip = group(zipbr)
	egen st = group(state)
	egen ct = group(city)
	egen zip_week = group(id_week zipbr)
// 
* baseline per-post TWFE for the DiD specification

eststo: reghdfe devices_store treatedxpost, vce(cl zip) absorb(id_store id_week) 
	
* generate traffic (according to advan definition, devices_plot/devices) (log)
foreach x in _store _plot _store_or_plot {
	gen traffic`x' = devices`x' / devices
	* traffic per million devices 
	replace traffic`x' = traffic`x'*1000000
}

save "$datadir/temp_weekly_traffic", replace

*** generate raw trends of devices and traffic around September 2016 (Event week)
* check traffic measures around September 2016
use "$datadir/temp_weekly_traffic", clear
collapse (mean) devices_store traffic_store *_plot, by(id_week)
twoway (tsline devices_store) (tsline devices_plot) (tsline devices_store_or_plot), ///
graphregion(color(white)) xline(57, lcolor(black))
graph export "$figdir/devices_time_trend.pdf", replace
twoway (tsline traffic_store) (tsline traffic_plot) (tsline traffic_store_or_plot), ///
graphregion(color(white)) xline(57, lcolor(black))
graph export "$figdir/traffic_time_trend.pdf", replace

* check traffic measures by treatment and control around September 2016
use "$datadir/temp_weekly_traffic", clear
collapse (mean) devices_store traffic_store *_plot, by(id_week treated)
reshape wide *_store *_plot, i(id_week) j(treated)

foreach x in devices_store devices_plot devices_store_or_plot traffic_store traffic_plot traffic_store_or_plot {
	label var `x'0 "`x' (control)"
	label var `x'1 "`x' (treated)"
}

foreach x in devices traffic {
	twoway (tsline `x'_store0, lcolor(red) lpattern(solid)) (tsline `x'_plot0, lcolor(blue) lpattern(solid)) (tsline `x'_store_or_plot0, lcolor(green) lpattern(solid)) ///
		(tsline `x'_store1, lcolor(red) lpattern(dash)) (tsline `x'_plot1, lcolor(blue) lpattern(dash)) (tsline `x'_store_or_plot1, lcolor(green) lpattern(dash)), ///
		legend(cols(3) size(6pt)) tline(57, lcolor(black)) graphregion(color(white))	
		graph export "$figdir/`x'_time_trend_bytreated.pdf", replace
}


*** use sample to generate event study (DiD) plots
use "$datadir/temp_weekly_traffic", clear
* winsorize traffic measures (kill large number of visits)

foreach x of varlist devices_store devices_plot devices_store_or_plot traffic_* {
	winsor2 `x', replace cuts(1 99)
}
 
foreach var of varlist devices_store devices_plot devices_store_or_plot traffic_* {
	if "`var'" == "devices_store" {
		reghdfe `var' treatedxpost, vce(cl zip) absorb(id_store id_week) 
		outreg2 using "$tabdir/twfe_main.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(2) replace ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)	
	}
	else {
		reghdfe `var' treatedxpost, vce(cl zip) absorb(id_store id_week) 
		outreg2 using "$tabdir/twfe_main.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(2) append ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)
	}
}
foreach var of varlist devices_store devices_plot devices_store_or_plot traffic_* {
	if "`var'" == "devices_store" {
		reghdfe `var' treatedxpost, vce(cl zip) absorb(id_store zip_week) 
		outreg2 using "$tabdir/twfe_main_zipweek.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(2) replace ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)	
	}
	else {
		reghdfe `var' treatedxpost, vce(cl zip) absorb(id_store zip_week) 
		outreg2 using "$tabdir/twfe_main_zipweek.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(2) append ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)
	}
}


*** dynamic regression tables and event-study plots
* generate dummies relative to wells fargo scandal week
forv i = 1/12 {
	bysort id_store (id_week): gen event_plus`i'weeks = 1 if id_week - event_week == `i' & treated == 1
	replace event_plus`i'weeks = 0 if event_plus`i'weeks >=.
}

forv i = 16(-1)1 {
	bysort id_store (id_week): gen event_minus`i'weeks = 1 if event_week - id_week == `i' & treated == 1
	replace event_minus`i'weeks = 0 if event_minus`i'weeks >=.
}
* dynamic regressions
* keep only those in the per-post period
keep if id_week-event_week <= 12 | id_week-event_week >= 16 //drop this result

foreach var of varlist devices_store devices_plot devices_store_or_plot traffic_* {
	if "`var'" == "devices_store" {
		reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store id_week) 
		outreg2 using "$tabdir/twfe_dynamic.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(2) replace ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)	
	}
	else {
		reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store id_week) 
		outreg2 using "$tabdir/twfe_dynamic.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(2) append ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)
	}
}
foreach var of varlist devices_store devices_plot devices_store_or_plot traffic_* {
	if "`var'" == "devices_store" {
		reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store zip_week) 
		outreg2 using "$tabdir/twfe_dynamic_zipweek.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(2) replace ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)	
	}
	else {
		reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store zip_week) 
		outreg2 using "$tabdir/twfe_dynamic_zipweek.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(2) append ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)
	}
}

/**************
	Figures
	***************/
// event study plots for dynamic regressions above 

foreach x in twfe_dynamic twfe_dynamic_zipweek {
	import delimited "$tabdir/`x'.txt", clear

	// v2 - devices_store; v3 - devices_plot; v4 - devices_store_or_plot
	// v5 - traffic_store; v6 - traffic_plot; v7 - traffic_store_or_plot

	* check if the correct numbers are dropped
	drop in 1/4
	drop in 59/66
	replace v1 = "se_" +  v1[_n-1] if v1=="" & v1[_n-1]!=""
	forval i = 2/7  {
		replace v`i' = subinstr(v`i', "]", "",.) 
		replace v`i' = subinstr(v`i', "[", "",.) 
		replace v`i' = "" if v`i' == "-" 
		replace v`i' = subinstr(v`i', "*", "",.) 
	}	

	foreach v of varlist v2-v7 {
		destring `v', replace
		replace `v' = 0 if v1 == "Constant"
		replace `v' = 0 if v1 == "se_Constant"
	}

	egen week = seq(), from(-16) block(2)
	* note that constant is week 0, hence need to shift weeks after event +1
	replace week = week + 1 if week >= 0
	replace week = 0 if week == 13 // make constant to be the event date 
	replace v1 = "event" if v1 == "Constant"
	replace v1 = "se_event" if v1 == "se_Constant"
	replace v1 = substr(v1, 1, 2)
	reshape wide v2-v7, i(week) j(v1) string

	foreach v in v2 v3 v4 v5 v6 v7 {
		rename `v'ev `v'coef
		rename `v'se `v'se
		gen `v'll = `v'coef - `v'se*1.96
		gen `v'uu = `v'coef + `v'se*1.96
	}

	if "`x'" == "twfe_dynamic" local name "week" 
	if "`x'" == "twfe_dynamic_zipweek" local name "zipweek" 
	* raw device plots
	#delimit ;
	twoway
		(rcap v2ll v2uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v2coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-16(1)12, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Coefficient") $gpr
		ylabel(-2(1)1) graphregion(color(white));
	#delimit cr
	graph export "$figdir/devices_store_evolution_`name'.pdf", replace
	#delimit ;
	twoway
		(rcap v3ll v3uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v3coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-16(1)12, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Coefficient") $gpr
		ylabel(-2(1)1) graphregion(color(white));
	#delimit cr
	graph export "$figdir/devices_plot_evolution_`name'.pdf", replace
	#delimit ;
	twoway
		(rcap v4ll v4uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v4coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-16(1)12, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Coefficient") $gpr
		ylabel(-2(1)1) graphregion(color(white));
	#delimit cr
	graph export "$figdir/devices_store_or_plot_evolution_`name'.pdf", replace

	* traffic plots
	#delimit ;
	twoway
		(rcap v5ll v5uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v5coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-16(1)12, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Coefficient") $gpr
		ylabel(-.3(.1).1) graphregion(color(white));
	#delimit cr
	graph export "$figdir/traffic_store_evolution_`name'.pdf", replace
	#delimit ;
	twoway
		(rcap v6ll v6uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v6coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-16(1)12, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Coefficient") $gpr
		ylabel(-.3(.1).1) graphregion(color(white));
	#delimit cr
	graph export "$figdir/traffic_plot_evolution_`name'.pdf", replace
	#delimit ;
	twoway
		(rcap v7ll v7uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v7coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-16(1)12, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Coefficient") $gpr
		ylabel(-.3(.1).1) graphregion(color(white));
	#delimit cr
	graph export "$figdir/traffic_store_or_plot_evolution_`name'.pdf", replace
	
}


********************************************************************************
capture log close
exit
