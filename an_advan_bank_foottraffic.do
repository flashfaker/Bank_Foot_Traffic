* create crosswalk between advan foot traffic data store_id and sod branch id
local fname an_advan_bank_foottraffic

******************************* SYNOPSIS ***************************************
/* 
Purpose: Analyze the cleaned weekly foot traffic data of 82 banks from Advan

Author: Zirui Song
Date Created: Jul 21st, 2022
Date Modified: Jan 5th, 2023

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
	* 13 unmatched banks from the crosswalk (i.e., not showing up in Advan foot traffic data)
	keep if _merge == 3
	drop _merge
	save "$datadir/cleaned data/weekly_advan_traffic_mergedbanks_updated20221004", replace
	
/**************
	Prediction Model for Advan
	***************/	
		
*** prepare/clean SOD data due to missing uninumbr for some obs (not important, all before year 2011) 
	use "$datadir/source data/SOD/sodupdate2021", clear
	drop if uninumbr == .
	tempfile crosswalk_sod
	save `crosswalk_sod'
	
	use "$datadir/cleaned data/weekly_advan_traffic_mergedbanks_updated20221004", clear
*** generate annual average foot traffic for each id_store (use 6/30 as the date (i.e., week 26) for annual split)
*** use the last half year in 2015 and first 26 weeks in 2016 as year 1, and 2022 data ends with week 27 
	drop if year == 2015 & week < 26
	gen ayear = 2016 if year == 2015 | (year == 2016 & week <= 26)
	foreach y of numlist 2016/2021 {
		local yearplus1 = `y' + 1
		replace ayear = `yearplus1' if (year == `y' & week > 26) | (year == `yearplus1' & week <= 26)
	}
	* deal with 2022 week 27 situation (drop for now, as it belongs to the data in next year)
	drop if year == 2022 & week > 26
	* this is to match SOD's June 30th report of total assets/deposits, etc.
	
*** collapse to get annual average of traffic 
	collapse (mean) devices* dwelled_* employees (first) uninumbr, by(ayear id_store)
	rename ayear year
	* as SOD haven't updated to 2022, drop those obs
	drop if year == 2022
	
*** merge with SOD data 
	fmerge 1:1 uninumbr year using "`crosswalk_sod'"
		drop if _merge == 2
/*

    Result                           # of obs.
    -----------------------------------------
    not matched                     2,127,850
        from master                    12,404  (_merge==1)
        from using                  2,115,446  (_merge==2)

    matched                           172,674  (_merge==3)
    -----------------------------------------

	manually check the unmatched 12,404 obs from master show that most unmatched
	observations are in 2019-2021, due to closing of bank branches probably
	* this is somewhat reflected in the large amount of 0s for "dwelled_store" variable,
	which records the number of devices dwelling more than 5 minutes at the store 
*/
	drop if _merge == 1
	drop _merge 
	
*** simple linear regression models 
	* substract employees from the devices/dwelled traffic
	foreach x in devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot {
		replace `x' = `x' - employees if `x' > employees // this is to take into account that we obtain a negative traffic in the end, which doesn't make sense
	}
	
	* Add Dec 15th of 2022 -- Need to Check if We have Zero Values
	sum devices_store devices_plot devices_store_or_plot dwelled_*
	* zero values for devices_store/plot and all dwelled variables
	* Add a 0.1 to each variable to get rid of the zero problem
	foreach x of varlist devices_store devices_plot devices_store_or_plot dwelled_* {
		replace `x' = `x' + 0.1
	} 
	
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
	
***	* (added 2022/10/05 -- also generate dwelled traffic (raw or traffic))
	
	* generate dwelled traffic (according to advan definition, devices_plot/devices)
	foreach x in dwelled_store dwelled_plot dwelled_store_or_plot employees {
		gen tf_`x' = `x' / devices
	}
	* generate annual change in raw foot traffic
	foreach var of varlist dwelled_store dwelled_plot dwelled_store_or_plot employees {
		bysort id_store (year): gen delta_`var' = (`var'[_n] - `var'[_n-1]) / `var'[_n-1]
		bysort id_store (year): gen logdiff_`var' = ln(`var'[_n]) - ln(`var'[_n-1])
	}
	* generate annual change in traffic as defined above
	foreach var of varlist tf_dwelled_store tf_dwelled_plot tf_dwelled_store_or_plot tf_employees {
		bysort id_store (year): gen delta_`var' = (`var'[_n] - `var'[_n-1]) / `var'[_n-1]
		bysort id_store (year): gen logdiff_`var' = ln(`var'[_n]) - ln(`var'[_n-1])
	}
	
*** log all the RHS variables (to interpret in terms of elasticities)
	
	foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot tf_dwelled_store tf_dwelled_plot tf_dwelled_store_or_plot tf_employees {
		replace `var' = ln(`var')
	}
	
*** label variables for tables
label var devices_store "ln(Devices in Store)"
label var devices_plot "ln(Devices in Parking Plot)"
label var devices_store_or_plot "ln(Devices in Store or Parking Plot)"
label var traffic_store "ln(Traffic in Store)"
label var traffic_plot "ln(Traffic in Parking Plot)"
label var traffic_store_or_plot "ln(Traffic in Store or Parking Lot)"
label var dwelled_store "ln(Dwelled Devices in Store)"
label var dwelled_plot "ln(Dwelled Devices in Parking Plot)"
label var dwelled_store_or_plot "ln(Dwelled Devices in Store or Parking Plot)"
label var tf_dwelled_store "ln(Dwelled Traffic in Store)"
label var tf_dwelled_plot "ln(Dwelled Traffic in Parking Plot)"
label var tf_dwelled_store_or_plot "ln(Dwelled Traffic in Store or Parking Lot)"

*** manipulation of bank deposits variable
	save "$datadir/temp_annual_dep_traffic_wbkmo", replace

	* (added 2022/10/05 -- drop the headquarter banks as those banks likely include deposits
	* that are not necessarily retail deposits)
	drop if bkmo == 1
	* generate log deposits and log-diff deposits 
	gen logdepsumbr = ln(depsumbr)
	bysort id_store (year): gen deltadepsumbr = (depsumbr[_n] - depsumbr[_n-1]) / depsumbr[_n-1]
	bysort id_store (year): gen logdiffdepsumbr = logdepsumbr[_n] - logdepsumbr[_n-1]
	
	// create winsorized depsumbr variables 
	winsor2 depsumbr, cuts(1 99)
	gen logdepsumbr_w = ln(depsumbr_w)
	bysort id_store (year): gen deltadepsumbr_w = (depsumbr_w[_n] - depsumbr_w[_n-1]) / depsumbr_w[_n-1]
	bysort id_store (year): gen logdiffdepsumbr_w = logdepsumbr_w[_n] - logdepsumbr_w[_n-1]	
	
	* label deposits 
	label var logdepsumbr_w "ln(Annual Deposits)"
	label var logdepsumbr "ln(Annual Deposits (Un-winsorized))"

save "$datadir/temp_annual_dep_traffic", replace

*** without dropping bank headquarters (bkmo == 1)
	use "$datadir/temp_annual_dep_traffic_wbkmo", clear
	* generate log deposits and log-diff deposits 
	gen logdepsumbr = ln(depsumbr)
	bysort id_store (year): gen deltadepsumbr = (depsumbr[_n] - depsumbr[_n-1]) / depsumbr[_n-1]
	bysort id_store (year): gen logdiffdepsumbr = logdepsumbr[_n] - logdepsumbr[_n-1]
	
	// create winsorized depsumbr variables 
	winsor2 depsumbr, cuts(1 99)
	gen logdepsumbr_w = ln(depsumbr_w)
	bysort id_store (year): gen deltadepsumbr_w = (depsumbr_w[_n] - depsumbr_w[_n-1]) / depsumbr_w[_n-1]
	bysort id_store (year): gen logdiffdepsumbr_w = logdepsumbr_w[_n] - logdepsumbr_w[_n-1]	
	
	* label deposits 
	label var logdepsumbr_w "ln(Annual Deposits)"
	label var logdepsumbr "ln(Annual Deposits (Un-winsorized))"
	
save "$datadir/temp_annual_dep_traffic_wbkmo", replace

*********************************************************************************
/* ADVAN REPORT OUTPUT TABLES (Into Latex Form) */
*********************************************************************************	
use "$datadir/temp_annual_dep_traffic", replace

*** Summary Statistics Table ***

estpost sum logdepsumbr_w devices_store devices_plot devices_store_or_plot traffic_store traffic_plot traffic_store_or_plot dwelled_* tf_dwelled_*
esttab using "$tabdir/advan report/Summary Statistics.tex", replace ///
cells("count(fmt(%9.0fc)) mean(fmt(%9.3f)) sd(fmt(%9.3f)) min(fmt(%9.3f)) max(fmt(%9.3f))") ///
label noobs nonum collabels(Count Mean "Std. Dev." Min Max)


*** Table 1 *** 
* main regression table (devices variables with windorized deposits, without bkmo)
foreach var of varlist devices_store devices_plot devices_store_or_plot traffic_store traffic_plot traffic_store_or_plot {
	eststo: reghdfe logdepsumbr_w `var', absorb(year id_store) vce(cl zipbr)
}
esttab using "$tabdir/advan report/Table1.tex", replace ///
nodepvars nomti nonum collabels(none) label b(3) se(3) parentheses ///
star(* 0.10 ** 0.05 *** 0.01) ar2 plain lines fragment noconstant
* clear storeed est
eststo clear

*** Table 2 ***
* ROBUSTNESS: dwelled traffic outcome variables instead
foreach var of varlist dwelled_* tf_dwelled_* {
	eststo: reghdfe logdepsumbr_w `var', absorb(year id_store) vce(cl zipbr)
}
esttab using "$tabdir/advan report/Table2.tex", replace ///
nodepvars nomti nonum collabels(none) label b(3) se(3) parentheses ///
star(* 0.10 ** 0.05 *** 0.01) ar2 plain lines fragment noconstant
* clear storeed est
eststo clear

*** Table 3 ***
* ROBUSTNESS: use unwinsorized log deposits instead
foreach var of varlist devices_store devices_plot devices_store_or_plot traffic_store traffic_plot traffic_store_or_plot {
	eststo: reghdfe logdepsumbr `var', absorb(year id_store) vce(cl zipbr)
}
esttab using "$tabdir/advan report/Table3.tex", replace ///
nodepvars nomti nonum collabels(none) label b(3) se(3) parentheses ///
star(* 0.10 ** 0.05 *** 0.01) ar2 plain lines fragment noconstant
* clear storeed est
eststo clear

*** Table 4 ***
* ROBUSTNESS: check results without dropping bank headquarters
use "$datadir/temp_annual_dep_traffic_wbkmo", replace
foreach var of varlist devices_store devices_plot devices_store_or_plot traffic_store traffic_plot traffic_store_or_plot {
	eststo: reghdfe logdepsumbr_w `var', absorb(year id_store) vce(cl zipbr)
}
esttab using "$tabdir/advan report/Table4.tex", replace ///
nodepvars nomti nonum collabels(none) label b(3) se(3) parentheses ///
star(* 0.10 ** 0.05 *** 0.01) ar2 plain lines fragment noconstant
* clear storeed est
eststo clear

*** Table 5 and 6 ***
* ROBUSTNESS: check results with different FE structures
use "$datadir/temp_annual_dep_traffic", replace
egen state_year_fe = group(stalpbr year)
egen county_year_fe = group(cntynumb year)

* table 5 (state x year FE)
foreach var of varlist devices_store devices_plot devices_store_or_plot traffic_store traffic_plot traffic_store_or_plot {
	eststo: reghdfe logdepsumbr_w `var', absorb(state_year_fe id_store) vce(cl zipbr)
}
esttab using "$tabdir/advan report/Table5.tex", replace ///
nodepvars nomti nonum collabels(none) label b(3) se(3) parentheses ///
star(* 0.10 ** 0.05 *** 0.01) ar2 plain lines fragment noconstant
* clear storeed est
eststo clear

* table 6 (county X year FE)
foreach var of varlist devices_store devices_plot devices_store_or_plot traffic_store traffic_plot traffic_store_or_plot {
	eststo: reghdfe logdepsumbr_w `var', absorb(county_year_fe id_store) vce(cl zipbr)
}
esttab using "$tabdir/advan report/Table6.tex", replace ///
nodepvars nomti nonum collabels(none) label b(3) se(3) parentheses ///
star(* 0.10 ** 0.05 *** 0.01) ar2 plain lines fragment noconstant
* clear storeed est
eststo clear

*********************************************************************************
* heterogeneity test by earlier years and later years as well as bank sizes

*** Table 7 and 8 *** (regressions of 3 early years and 3 later years)
use "$datadir/temp_annual_dep_traffic", replace
keep if year <= 2018
foreach var of varlist devices_store devices_plot devices_store_or_plot traffic_store traffic_plot traffic_store_or_plot {
	eststo: reghdfe logdepsumbr_w `var', absorb(year id_store) vce(cl zipbr)
}
esttab using "$tabdir/advan report/Table_earlyyears.tex", replace ///
nodepvars nomti nonum collabels(none) label b(3) se(3) parentheses ///
star(* 0.10 ** 0.05 *** 0.01) ar2 plain lines fragment noconstant
* clear storeed est
eststo clear

use "$datadir/temp_annual_dep_traffic", replace
keep if year > 2018
foreach var of varlist devices_store devices_plot devices_store_or_plot traffic_store traffic_plot traffic_store_or_plot {
	eststo: reghdfe logdepsumbr_w `var', absorb(year id_store) vce(cl zipbr)
}
esttab using "$tabdir/advan report/Table_lateryears.tex", replace ///
nodepvars nomti nonum collabels(none) label b(3) se(3) parentheses ///
star(* 0.10 ** 0.05 *** 0.01) ar2 plain lines fragment noconstant
* clear storeed est
eststo clear

*** Table 9 and 10 *** (regressions of large banks and small banks)
* obtain median bank asset size (avg across 6 years) threshold first
use "$datadir/temp_annual_dep_traffic", replace
preserve
	collapse (mean) asset, by(rssdid)
	egen median_asset = pctile(asset), p(90)
	gen large_bank = 1 if asset >= median_asset
	replace large_bank = 0 if asset < median_asset
	tab large_bank
	tempfile asset_median_split
	save `asset_median_split'
restore
fmerge m:1 rssdid using `asset_median_split', keepusing(large_bank) nogen
tab large_bank
* 99 percent of obs are from large banks, so splitting by bank size doesn't quite work... Still below are the results

preserve 
	keep if large_bank == 1
	foreach var of varlist devices_store devices_plot devices_store_or_plot traffic_store traffic_plot traffic_store_or_plot {
		eststo: reghdfe logdepsumbr_w `var', absorb(year id_store) vce(cl zipbr)
	}
	esttab using "$tabdir/advan report/Table_largebanks.tex", replace ///
	nodepvars nomti nonum collabels(none) label b(3) se(3) parentheses ///
	star(* 0.10 ** 0.05 *** 0.01) ar2 plain lines fragment noconstant
	* clear storeed est
	eststo clear
restore
preserve
	keep if large_bank == 0
	foreach var of varlist devices_store devices_plot devices_store_or_plot traffic_store traffic_plot traffic_store_or_plot {
		eststo: reghdfe logdepsumbr_w `var', absorb(year id_store) vce(cl zipbr)
	}
	esttab using "$tabdir/advan report/Table_smallbanks.tex", replace ///
	nodepvars nomti nonum collabels(none) label b(3) se(3) parentheses ///
	star(* 0.10 ** 0.05 *** 0.01) ar2 plain lines fragment noconstant
	* clear storeed est
	eststo clear
restore


*********************************************************************************
/* sensitivity test for main regression models (DiD) with Year + Id_Store FE structures */
*********************************************************************************	
*** this section tests the sensitivity of main results using sample that drops bkmo 
*** or sample that doesn't drop bkmo

*** main regressions -- raw regressions of elasticity and log-diff of deposits and traffic
use "$datadir/temp_annual_dep_traffic_wbkmo", clear
reghdfe logdepsumbr_w devices_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) replace ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, Yes)	
*** 
use "$datadir/temp_annual_dep_traffic", clear
reghdfe logdepsumbr_w devices_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, No)	
***
use "$datadir/temp_annual_dep_traffic_wbkmo", clear
reghdfe logdepsumbr_w dwelled_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, Yes)	
*** 
use "$datadir/temp_annual_dep_traffic", clear
reghdfe logdepsumbr_w dwelled_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, No)	
***
use "$datadir/temp_annual_dep_traffic_wbkmo", clear
reghdfe logdepsumbr_w traffic_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, Yes)	
*** 
use "$datadir/temp_annual_dep_traffic", clear
reghdfe logdepsumbr_w traffic_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, No)	
***
use "$datadir/temp_annual_dep_traffic_wbkmo", clear
reghdfe logdepsumbr_w tf_dwelled_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, Yes)	
*** 
use "$datadir/temp_annual_dep_traffic", clear
reghdfe logdepsumbr_w tf_dwelled_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, No)	
***
use "$datadir/temp_annual_dep_traffic_wbkmo", clear
reghdfe logdiffdepsumbr_w logdiff_devices_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, Yes)	
*** 
use "$datadir/temp_annual_dep_traffic", clear
reghdfe logdiffdepsumbr_w logdiff_devices_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, No)	
***
use "$datadir/temp_annual_dep_traffic_wbkmo", clear
reghdfe logdiffdepsumbr_w logdiff_dwelled_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, Yes)	
*** 
use "$datadir/temp_annual_dep_traffic", clear
reghdfe logdiffdepsumbr_w logdiff_dwelled_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, No)	
***
use "$datadir/temp_annual_dep_traffic_wbkmo", clear
reghdfe logdiffdepsumbr_w logdiff_traffic_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, Yes)	
*** 
use "$datadir/temp_annual_dep_traffic", clear
reghdfe logdiffdepsumbr_w logdiff_traffic_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, No)	
***
use "$datadir/temp_annual_dep_traffic_wbkmo", clear
reghdfe logdiffdepsumbr_w logdiff_tf_dwelled_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, Yes)	
*** 
use "$datadir/temp_annual_dep_traffic", clear
reghdfe logdiffdepsumbr_w logdiff_tf_dwelled_store, absorb(year id_store) vce(cl zipbr)
outreg2 using "$tabdir/sensitivity_tests.xls", /// 
title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
bracket bdec(4) sdec(4) append ///
addtext(Branch FE, Yes, Year FE, Yes, With Bank Headquarters, No)	
*********************************************************************************
/* main regression models (DiD) with Year + Id_Store FE structures */
*********************************************************************************	
	
	use "$datadir/temp_annual_dep_traffic", clear
	
* simple linear regression models based on raw foot traffic
	* output regression tables with log traffic on log deposits
foreach y of varlist depsumbr logdepsumbr deltadepsumbr depsumbr_w logdepsumbr_w deltadepsumbr_w {
	foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot tf_dwelled_store tf_dwelled_plot tf_dwelled_store_or_plot tf_employees {
		if "`var'" == "devices_store" {
			reghdfe `y' `var', absorb(year id_store) 
			outreg2 using "$tabdir/`y'_traffic_prediction_model_raw.xls", /// 
			title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Year FE, Yes)	
		}
		else {
			reghdfe `y' `var', absorb(year id_store) 
			outreg2 using "$tabdir/`y'_traffic_prediction_model_raw.xls", /// 
			title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Year FE, Yes)
		}
	}
	* add clustering by state
	foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot tf_dwelled_store tf_dwelled_plot tf_dwelled_store_or_plot tf_employees {
		if "`var'" == "devices_store" {
			reghdfe `y' `var', absorb(year id_store) vce(cl stnumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_raw_clst.xls", /// 
			title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at state level)	
		}
		else {
			reghdfe `y' `var', absorb(year id_store) vce(cl stnumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_raw_clst.xls", /// 
			title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at state level)
		}
	}
	* add clustering by county
	foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot tf_dwelled_store tf_dwelled_plot tf_dwelled_store_or_plot tf_employees {
		if "`var'" == "devices_store" {
			reghdfe `y' `var', absorb(year id_store) vce(cl cntynumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_raw_clcnty.xls", /// 
			title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at county level)	
		}
		else {
			reghdfe `y' `var', absorb(year id_store) vce(cl cntynumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_raw_clcnty.xls", /// 
			title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at county level)
		}
	}
	* add clustering by zip 
	foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot tf_dwelled_store tf_dwelled_plot tf_dwelled_store_or_plot tf_employees {
		if "`var'" == "devices_store" {
			reghdfe `y' `var', absorb(year id_store) vce(cl zipbr)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_raw_clzip.xls", /// 
			title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at zip level)	
		}
		else {
			reghdfe `y' `var', absorb(year id_store) vce(cl zipbr)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_raw_clzip.xls", /// 
			title ("Annual Traffic on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Year FE, Yes, Note: standard errors clustering at zip level)
		}
	}
}

* simple linear regression models based on (growth rates of traffic)
	* output regression tables with period-on-period percentage change of traffic and log deposits
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

*********************************************************************************
/*same regression models but with stateXyear or countyXyear FE and branch FE structures (using only winsorized deposits)*/
*********************************************************************************

use "$datadir/temp_annual_dep_traffic", clear

* generate state year fe structure
egen state_year_fe = group(stalpbr year)
egen county_year_fe = group(cntynumb year)

*** County X Year FEs
* log diff models with countyXyear FEs
foreach y of varlist logdiffdepsumbr_w {
	* clustering by zip
	foreach var of varlist logdiff_* {
		if "`var'" == "logdiff_devices_store" {
			reghdfe `y' `var', absorb(county_year_fe id_store) vce(cl zipbr)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_cntyyr.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, CountyXYear FE, Yes)	
		}
		else {
			reghdfe `y' `var', absorb(county_year_fe id_store) vce(cl zipbr)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_cntyyr.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, CountyXYear FE, Yes)
		}
	}
}

* raw association models with countyXyear FEs
foreach y of varlist logdepsumbr logdepsumbr_w {
	* clustering by zip
	foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot tf_dwelled_store tf_dwelled_plot tf_dwelled_store_or_plot tf_employees {
		if "`var'" == "devices_store" {
			reghdfe `y' `var', absorb(county_year_fe id_store) vce(cl zipbr)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_cntyyr.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, CountyXYear FE, Yes)	
		}
		else {
			reghdfe `y' `var', absorb(county_year_fe id_store) vce(cl zipbr)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_cntyyr.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, CountyXYear FE, Yes)
		}
	}
}

*** State X Year FEs
* again, log diff models with winsorized deposits and traffic measures as wellas branch and stateXyear FEs 
foreach y of varlist logdiffdepsumbr_w {
	foreach var of varlist logdiff_* {
		if "`var'" == "logdiff_devices_store" {
			reghdfe `y' `var', absorb(state_year_fe id_store) 
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, StateXYear FE, Yes)	
		}
		else {
			reghdfe `y' `var', absorb(state_year_fe id_store) 
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, StateXYear FE, Yes)
		}
	}
	* add clustering by state
	foreach var of varlist logdiff_* {
		if "`var'" == "logdiff_devices_store" {
			reghdfe `y' `var', absorb(state_year_fe id_store) vce(cl stnumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr_clst.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, StateXYear FE, Yes, Note: standard errors clustering at state level)	
		}
		else {
			reghdfe `y' `var', absorb(state_year_fe id_store) vce(cl stnumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr_clst.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(2) append ///
			addtext(Branch FE, Yes, StateXYear FE, Yes, Note: standard errors clustering at state level)
		}
	}
	* add clustering by county
	foreach var of varlist logdiff_* {
		if "`var'" == "logdiff_devices_store" {
			reghdfe `y' `var', absorb(state_year_fe id_store) vce(cl cntynumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr_clcnty.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, StateXYear FE, Yes, Note: standard errors clustering at county level)	
		}
		else {
			reghdfe `y' `var', absorb(state_year_fe id_store) vce(cl cntynumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr_clcnty.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, StateXYear FE, Yes, Note: standard errors clustering at county level)
		}
	}
	* add clustering by zip 
	foreach var of varlist logdiff_* {
		if "`var'" == "logdiff_devices_store" {
			reghdfe `y' `var', absorb(state_year_fe id_store) vce(cl zipbr)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr_clzip.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, StateXYear FE, Yes, Note: standard errors clustering at zip level)	
		}
		else {
			reghdfe `y' `var', absorb(state_year_fe id_store) vce(cl zipbr)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr_clzip.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, StateXYear FE, Yes, Note: standard errors clustering at zip level)
		}
	}
}

* also output the raw associations between deposits and traffic changes using stateXyear FEs 
* only check the raw and logged deposits (after winsorization) this time
foreach y of varlist depsumbr_w logdepsumbr_w {
	foreach var of varlist delta_* {
		if "`var'" == "delta_devices_store" {
			reghdfe `y' `var', absorb(state_year_fe id_store) 
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, StateXYear FE, Yes)	
		}
		else {
			reghdfe `y' `var', absorb(state_year_fe id_store) 
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, StateXYear FE, Yes)
		}
	}
	* add clustering by state
	foreach var of varlist delta_* {
		if "`var'" == "delta_devices_store" {
			reghdfe `y' `var', absorb(state_year_fe id_store) vce(cl stnumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_clst.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, StateXYear FE, Yes, Note: standard errors clustering at state level)	
		}
		else {
			reghdfe `y' `var', absorb(state_year_fe id_store) vce(cl stnumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr_clst.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, StateXYear FE, Yes, Note: standard errors clustering at state level)
		}
	}
	* add clustering by county
	foreach var of varlist delta_* {
		if "`var'" == "delta_devices_store" {
			reghdfe `y' `var', absorb(state_year_fe id_store) vce(cl cntynumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr_clcnty.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, StateXYear FE, Yes, Note: standard errors clustering at county level)	
		}
		else {
			reghdfe `y' `var', absorb(state_year_fe id_store) vce(cl cntynumb)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr_clcnty.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, StateXYear FE, Yes, Note: standard errors clustering at county level)
		}
	}
	* add clustering by zip 
	foreach var of varlist delta_* {
		if "`var'" == "delta_devices_store" {
			reghdfe `y' `var', absorb(state_year_fe id_store) vce(cl zipbr)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr_clzip.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, StateXYear FE, Yes, Note: standard errors clustering at zip level)	
		}
		else {
			reghdfe `y' `var', absorb(state_year_fe id_store) vce(cl zipbr)
			outreg2 using "$tabdir/`y'_traffic_prediction_model_styr_clzip.xls", /// 
			title ("Annual Traffic Change on Branch Deposits") ctitle("`y'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, StateXYear FE, Yes, Note: standard errors clustering at zip level)
		}
	}
}

/**************
	Event Study (DiD) w.r.t. Wells Fargo Scandal
	***************/	

*** create closest bank branch pair (wells fargo to other banks) using sod (
*** but only those uninumbr matched to advan data)
use "$datadir/source data/SOD/sodupdate2021", clear
drop if uninumbr == .
collapse (median) sims_latitude sims_longitude (first) stalpbr, by(uninumbr) //keep stcntybr so that we only compute distances within a county (to minimize computation required)
drop if sims_latitude == . | sims_longitude == .
* merge with advan data so that we don't identify branches not in the advan data set
merge 1:m uninumbr using "$datadir/cleaned data/weekly_advan_traffic_mergedbanks_updated20221004", keepusing(id_store)
keep if _merge == 3
drop _merge 
collapse (median) sims_latitude sims_longitude (first) stalpbr, by(uninumbr)  

* joinby stcntybr for calculation of distances
tempfile sod_dist
save `sod_dist'
rename uninumbr key_uninumbr 
rename (sims_latitude sims_longitude) (key_lat key_long)
joinby stalpbr using `sod_dist'

* calculate distances
drop if key_uninumbr == uninumbr // drop self 
geodist key_lat key_long sims_latitude sims_longitude, gen(dist)
// keep 5 smallest distances in case that the closest one is still a Wells Fargo bank
bysort key_uninumbr (dist): keep if _n <= 5
save "$datadir/cleaned data/sod_branch_dist_2021", replace

*** Added 2022/10/12 (closest branch to Wells Fargo branch)
use "$datadir/cleaned data/weekly_advan_traffic_mergedbanks_updated20221004", clear
*** generate Wells Fargo dummy so that we map nearest bank to Wells Fargo bank branch
keep if strpos(bank_name, "wells fargo") != 0 
keep uninumbr
duplicates drop 
tempfile wells_fargo_branches
save `wells_fargo_branches'
rename uninumbr key_uninumbr
// merge on key_uninumbr to get only wells fargo bank matches
merge 1:m key_uninumbr using "$datadir/cleaned data/sod_branch_dist_2021.dta", keepusing(uninumbr dist)
keep if _merge == 3
drop _merge
// merge on uninumbr to make sure that the matched branches do not have Wells Fargo branches
merge m:1 uninumbr using `wells_fargo_branches'
* drop _merge == 3 (those are wells fargo branches get matched to one wells fargo branch)
drop if _merge == 3 
drop if _merge == 2 // (don't need using data)
drop _merge 
* notice that there are duplicates of uninumbr (meaning multiple branches matched to different Wells Fargo branches)
* use the one that's closest to an Wells Fargo bank and then drop the other one 
bysort uninumbr (dist): keep if _n == 1
*** without the step specified above, we allow wells-fargo-other-branch pairs to have duplicates branch in different pairs
* now take the smallest distances 
bysort key_uninumbr (dist): keep if _n == 1

save "$datadir/cleaned data/wells_fargo_nearest_branch.dta", replace

***************************** begin Event Study ********************************
********************************************************************************
use "$datadir/cleaned data/weekly_advan_traffic_mergedbanks_updated20221004", clear
* sample begins from the second half of 2015
drop if year == 2015 & week < 26
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
	* generate fixed effects structures
	egen zip = group(zipbr)
	egen st = group(state)
	egen ct = group(state city) // as different cities in two states might somehow have the same name
	egen zip_week = group(id_week zipbr)
// 
* baseline per-post TWFE for the DiD specification

eststo: reghdfe devices_store treatedxpost, vce(cl zip) absorb(id_store id_week) 
	
* generate traffic (according to advan definition, devices_plot/devices) (log)
foreach x in _store _plot _store_or_plot {
	replace devices`x' = devices`x' - employees // subtract employees from our measure of traffic 
	gen traffic`x' = devices`x' / devices
	* log traffic in order to interpret it in elasticities
	replace traffic`x' = ln(traffic`x')
	replace devices`x' = ln(devices`x')
}
gen traffic_employees = employees / devices 
replace employees = ln(employees)
replace traffic_employees = ln(traffic_employees)
* generate traffic based on dwelled devices
foreach x in _store _plot _store_or_plot {
	replace dwelled`x' = dwelled`x' - employees // subtract employees from our measure of traffic 
	gen tf_dwelled`x' = dwelled`x' / devices
	* log traffic in order to interpret it in elasticities
	replace tf_dwelled`x' = ln(tf_dwelled`x')
	replace dwelled`x' = ln(dwelled`x')
}

save "$datadir/temp_weekly_traffic", replace

use "$datadir/temp_weekly_traffic", clear
*** add dummy variable indicating nearest neighbor bank branch 
preserve
	fmerge m:1 uninumbr using "$datadir/cleaned data/wells_fargo_nearest_branch.dta", keepusing(key_uninumbr dist)
	keep if _merge == 3 // all matched non-wells fargo branches with key_uninumbr (wells fargo branch
	drop _merge
	tempfile non_wf_branch
	save `non_wf_branch'
restore

rename uninumbr key_uninumbr
fmerge m:1 key_uninumbr using "$datadir/cleaned data/wells_fargo_nearest_branch.dta", keepusing(uninumbr dist)
* drop non-matches (meaning banks not nearest neighbor to Wells Fargo branch)
keep if _merge == 3 // all matched wells fargo branches with a nearest neighbor branch (non wells fargo) within the state
drop _merge
append using `non_wf_branch'

* generate an id from both the key_uninumbr (the identifying )
* get the smaller and bigger uninumbr so that we can use egen to get an id variable for pairs
egen first_uninumbr = rowmin(uninumbr key_uninumbr)
egen second_uninumbr = rowmax(uninumbr key_uninumbr)
egen pair = group(first_uninumbr second_uninumbr)

save "$datadir/temp_weekly_traffic_matchedbr", replace


/**************
	Raw Traffic Trends 
	***************/	
	
*** generate raw trends of devices and traffic around September 2016 (Event week)
* check traffic measures around September 2016
use "$datadir/temp_weekly_traffic", clear
* generate the local variable that is the treatment week (week 66) 
local t = event_week

collapse (mean) devices_store traffic_store *_plot, by(id_week)
twoway (tsline devices_store) (tsline devices_plot) (tsline devices_store_or_plot), ///
graphregion(color(white)) xline(`t', lcolor(black))
graph export "$figdir/devices_time_trend.pdf", replace
twoway (tsline traffic_store) (tsline traffic_plot) (tsline traffic_store_or_plot), ///
graphregion(color(white)) xline(`t', lcolor(black))
graph export "$figdir/traffic_time_trend.pdf", replace

* check traffic measures by treatment and control around September 2016
use "$datadir/temp_weekly_traffic", clear
* generate the local variable that is the treatment week (week 66) 
local t = event_week

collapse (mean) devices_store traffic_store *_plot, by(id_week treated)
reshape wide *_store *_plot, i(id_week) j(treated)

foreach x in devices_store devices_plot devices_store_or_plot traffic_store traffic_plot traffic_store_or_plot {
	label var `x'0 "`x' (control)"
	label var `x'1 "`x' (treated)"
}

foreach x in devices traffic {
	twoway (tsline `x'_store0, lcolor(red) lpattern(solid)) (tsline `x'_plot0, lcolor(blue) lpattern(solid)) (tsline `x'_store_or_plot0, lcolor(green) lpattern(solid)) ///
		(tsline `x'_store1, lcolor(red) lpattern(dash)) (tsline `x'_plot1, lcolor(blue) lpattern(dash)) (tsline `x'_store_or_plot1, lcolor(green) lpattern(dash)), ///
		legend(cols(3) size(6pt)) tline(`t', lcolor(black)) graphregion(color(white))	
		graph export "$figdir/`x'_time_trend_bytreated.pdf", replace
}

/**************
	Dynamic Regressions
	***************/
*** use sample to generate event study (DiD) plots
use "$datadir/temp_weekly_traffic", clear

/* winsorize traffic measures (kill large number of visits)
foreach x of varlist devices_store devices_plot devices_store_or_plot traffic_* {
	winsor2 `x', replace cuts(1 99)
}
*/
 
foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot traffic_employees tf_* {
	if "`var'" == "devices_store" {
		reghdfe `var' treatedxpost, vce(cl zip) absorb(id_store id_week) 
		outreg2 using "$tabdir/twfe_main.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(4) replace ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)	
	}
	else {
		reghdfe `var' treatedxpost, vce(cl zip) absorb(id_store id_week) 
		outreg2 using "$tabdir/twfe_main.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(4) append ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)
	}
}
foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot traffic_employees tf_* {
	if "`var'" == "devices_store" {
		reghdfe `var' treatedxpost, vce(cl zip) absorb(id_store zip_week) 
		outreg2 using "$tabdir/twfe_main_zipweek.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(4) replace ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)	
	}
	else {
		reghdfe `var' treatedxpost, vce(cl zip) absorb(id_store zip_week) 
		outreg2 using "$tabdir/twfe_main_zipweek.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(4) append ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)
	}
}

*********************************************************************************
/* pre-post with dwelled traffic using different event windows */
*********************************************************************************	
* new from Dec 6th, 2022
*** dynamic regression tables and event-study plots with different post windows 

* generate different event window data sets
forv j = 12(12)48 {
	use "$datadir/temp_weekly_traffic", clear
	* generate dummies relative to wells fargo scandal week
	forv i = 1/`j' {
		bysort id_store (id_week): gen event_plus`i'weeks = 1 if id_week - event_week == `i' & treated == 1
	replace event_plus`i'weeks = 0 if event_plus`i'weeks >=.
}

	forv i = 12(-1)1 {
		bysort id_store (id_week): gen event_minus`i'weeks = 1 if event_week - id_week == `i' & treated == 1
	replace event_minus`i'weeks = 0 if event_minus`i'weeks >=.
}
	* dynamic regressions
	* keep only those in the per-post period
	drop if event_week-id_week > 12 // drop the pre-trends that are more than 12 weeks before 
	drop if id_week-event_week > `j' //drop this post-trends that are more than `i' weeks after
	save "$datadir/temp_weekly_traffic_eventwindow_`j'.dta", replace // save this for later heterogeneity test-16 -> 12 or 24 or 36 or 48
}

* use different event windows to generate event study plots for dwelled device/traffic and 
* dwelled device or plot and 
forv i = 12(12)48 {
	use "$datadir/temp_weekly_traffic_eventwindow_`i'.dta", clear
	foreach var of varlist dwelled_store dwelled_plot dwelled_store_or_plot tf_* {
		if "`var'" == "dwelled_store" {
			reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store id_week) 
			outreg2 using "$tabdir/twfe_dynamic_dwelled_`i'.xls", /// 
			title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)	
		}
		else {
			reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store id_week) 
			outreg2 using "$tabdir/twfe_dynamic_dwelled_`i'.xls", /// 
			title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)
		}
	}
	foreach var of varlist dwelled_store dwelled_plot dwelled_store_or_plot tf_* {
		if "`var'" == "dwelled_store" {
			reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store zip_week) 
			outreg2 using "$tabdir/twfe_dynamic_zipweek_dwelled_`i'.xls", /// 
			title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)	
		}
		else {
			reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store zip_week) 
			outreg2 using "$tabdir/twfe_dynamic_zipweek_dwelled_`i'.xls", /// 
			title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)
		}
	}
}

* use different event windows generated above to generate different event study plots 

forv x = 12(12)48 {
	foreach file in twfe_dynamic_dwelled twfe_dynamic_dwelled_zipweek {
	import delimited "$tabdir/twfe_dynamic_dwelled_`x'.txt", clear

	// v2 - dwelled_store; v3 - dwelled_plot; v4 - dwelled_store_or_plot
	// v5 - tf_dwelled_store; v6 - tf_dwelled_store; v7 - tf_dwelled_store_or_plot

	* check if the correct numbers are dropped
	drop in 1/4
	* drop the bottom several lines 
	drop if v2 == ""
	drop if v1 == "Observations" | v1 == "R-squared"
	drop if v2 == "Yes"
	
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

	egen week = seq(), from(-12) block(2)
	* note that constant is week 0, hence need to shift weeks after event +1
	replace week = week + 1 if week >= 0
	local d = `x' + 1
	replace week = 0 if week == `d' // make constant to be the event date 
	replace v1 = "event" if v1 == "Constant"
	replace v1 = "se_event" if v1 == "se_Constant"
	replace v1 = substr(v1, 1, 2)
	reshape wide v2-v7, i(week) j(v1) string

	foreach v of numlist 2/7 {
		rename v`v'ev v`v'coef
		rename v`v'se v`v'se
		gen v`v'll = v`v'coef - v`v'se*1.96
		gen v`v'uu = v`v'coef + v`v'se*1.96
	}

	if "`file'" == "twfe_dynamic_dwelled" local name "week" 
	if "`file'" == "twfe_dynamic_dwelled_zipweek" local name "zipweek" 

	* raw device plots
	#delimit ;
	twoway
		(rcap v2ll v2uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v2coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)`x', val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Dwelled Store Devices") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/dwelled_store_evolution_`name'_`x'.pdf", replace
	#delimit ;
	twoway
		(rcap v3ll v3uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v3coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)`x', val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Dwelled Plot Devices") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/dwelled_plot_evolution_`name'_`x'.pdf", replace
	#delimit ;
	twoway
		(rcap v4ll v4uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v4coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)`x', val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Dwelled Store or Plot Devices") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/dwelled_store_or_plot_evolution_`name'_`x'.pdf", replace

	* dwelled device plots
	#delimit ;
	twoway
		(rcap v5ll v5uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v5coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)`x', val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Dwelled Store Traffic") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/tf_dwelled_store_evolution_`name'_`x'.pdf", replace
	#delimit ;
	twoway
		(rcap v6ll v6uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v6coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)`x', val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Dwelled Plot Traffic") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/tf_dwelled_plot_evolution_`name'_`x'.pdf", replace
	#delimit ;
	twoway
		(rcap v7ll v7uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v7coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)`x', val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Dwelled Store or Plot Traffic") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/tf_dwelled_store_or_plot_evolution_`name'_`x'.pdf", replace

	}
}


*********************************************************************************	

*** dynamic regression tables and event-study plots
use "$datadir/temp_weekly_traffic", clear
* generate dummies relative to wells fargo scandal week
forv i = 1/16 {
	bysort id_store (id_week): gen event_plus`i'weeks = 1 if id_week - event_week == `i' & treated == 1
	replace event_plus`i'weeks = 0 if event_plus`i'weeks >=.
}

forv i = 12(-1)1 {
	bysort id_store (id_week): gen event_minus`i'weeks = 1 if event_week - id_week == `i' & treated == 1
	replace event_minus`i'weeks = 0 if event_minus`i'weeks >=.
}
* dynamic regressions
* keep only those in the per-post period
drop if event_week-id_week > 12 // drop the pre-trends that are more than 12 weeks before 
drop if id_week-event_week > 16 //drop this post-trends that are more than 16 weeks after
save "$datadir/temp_weekly_traffic_eventwindow.dta", replace // save this for later heterogeneity test

foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot traffic_employees tf_* {
	if "`var'" == "devices_store" {
		reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store id_week) 
		outreg2 using "$tabdir/twfe_dynamic.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(4) replace ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)	
	}
	else {
		reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store id_week) 
		outreg2 using "$tabdir/twfe_dynamic.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(4) append ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)
	}
}
foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot traffic_employees tf_* {
	if "`var'" == "devices_store" {
		reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store zip_week) 
		outreg2 using "$tabdir/twfe_dynamic_zipweek.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(4) replace ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)	
	}
	else {
		reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store zip_week) 
		outreg2 using "$tabdir/twfe_dynamic_zipweek.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(4) append ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)
	}
}

* do the pair-wise regressions now 
use "$datadir/temp_weekly_traffic_matchedbr", clear

*** dynamic regression tables and event-study plots
* generate dummies relative to wells fargo scandal week
forv i = 1/16 {
	bysort id_store (id_week): gen event_plus`i'weeks = 1 if id_week - event_week == `i' & treated == 1
	replace event_plus`i'weeks = 0 if event_plus`i'weeks >=.
}

forv i = 12(-1)1 {
	bysort id_store (id_week): gen event_minus`i'weeks = 1 if event_week - id_week == `i' & treated == 1
	replace event_minus`i'weeks = 0 if event_minus`i'weeks >=.
}
* dynamic regressions
* keep only those in the per-post period
drop if event_week-id_week > 12 // drop the pre-trends that are more than 12 weeks before 
drop if id_week-event_week > 16 //drop this post-trends that are more than 16 weeks after
save "$datadir/temp_weekly_traffic_matchedbr_eventwindow.dta", replace // save this for later heterogeneity test

egen pair_week = group(pair id_week)
foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot traffic_employees tf_*{
	if "`var'" == "devices_store" {
		reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store pair_week) 
		outreg2 using "$tabdir/twfe_dynamic_pairwise.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(4) replace ///
		addtext(Branch FE, Yes, PairXWeek FE, Yes, Note: standard errors clustering at zip level)	
	}
	else {
		reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store pair_week) 
		outreg2 using "$tabdir/twfe_dynamic_pairwise.xls", /// 
		title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
		bracket bdec(4) sdec(4) append ///
		addtext(Branch FE, Yes, PairXWeek FE, Yes, Note: standard errors clustering at zip level)
	}
}

*********************************************************************************
/* check missing data for week 7, 8, 9 for dwelled traffic (unusual dips) */
*********************************************************************************	
* new from Dec 6th, 2022
use "$datadir/temp_weekly_traffic_eventwindow_48", clear
* collapse by year week to obtain the number of nonmissing observations for each week 
collapse (count) dwelled_* tf_*, by(year week)
gen date = yw(year, week)
format date %tw
* just get rid of week 53 for the plots
drop if date == .
tsset date

local t = yw(2016, 38)
local t1 = yw(2016, 45)
local t2 = yw(2016, 47)
twoway (tsline dwelled_store) (tsline dwelled_plot) (tsline dwelled_store_or_plot), ///
graphregion(color(white)) xline(`t', lcolor(black)) xline(`t1', lcolor(blue)) xline(`t2', lcolor(green))
graph export "$figdir/dwelled_devices_time_trend.pdf", replace

/**************
	Figures
	***************/
// event study plots for dynamic regressions above 

foreach x in twfe_dynamic twfe_dynamic_zipweek twfe_dynamic_pairwise {
	import delimited "$tabdir/`x'.txt", clear

	// v2 - devices_store; v3 - devices_plot; v4 - devices_store_or_plot
	// v5 - dwelled_store; v6 - dwelled_plot; v7 - dwelled_store_or_plot
	// v8 - employees
	// v9 - traffic_store; v10 - traffic_plot; v11 - traffic_store_or_plot
	// v12 - tf_dwelled_store; v13 - tf_dwelled_store; v14 - tf_dwelled_store_or_plot
	// v15 - traffic_employees

	* check if the correct numbers are dropped
	drop in 1/4
	drop in 59/66
	replace v1 = "se_" +  v1[_n-1] if v1=="" & v1[_n-1]!=""
	forval i = 2/15  {
		replace v`i' = subinstr(v`i', "]", "",.) 
		replace v`i' = subinstr(v`i', "[", "",.) 
		replace v`i' = "" if v`i' == "-" 
		replace v`i' = subinstr(v`i', "*", "",.) 
	}	

	foreach v of varlist v2-v15 {
		destring `v', replace
		replace `v' = 0 if v1 == "Constant"
		replace `v' = 0 if v1 == "se_Constant"
	}

	egen week = seq(), from(-12) block(2)
	* note that constant is week 0, hence need to shift weeks after event +1
	replace week = week + 1 if week >= 0
	replace week = 0 if week == 17 // make constant to be the event date 
	replace v1 = "event" if v1 == "Constant"
	replace v1 = "se_event" if v1 == "se_Constant"
	replace v1 = substr(v1, 1, 2)
	reshape wide v2-v15, i(week) j(v1) string

	foreach v of numlist 2/15 {
		rename v`v'ev v`v'coef
		rename v`v'se v`v'se
		gen v`v'll = v`v'coef - v`v'se*1.96
		gen v`v'uu = v`v'coef + v`v'se*1.96
	}

	if "`x'" == "twfe_dynamic" local name "week" 
	if "`x'" == "twfe_dynamic_zipweek" local name "zipweek" 
	if "`x'" == "twfe_dynamic_pairwise" local name "pairwise" 
	* raw device plots
	#delimit ;
	twoway
		(rcap v2ll v2uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v2coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)16, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Store Devices") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/devices_store_evolution_`name'.pdf", replace
	#delimit ;
	twoway
		(rcap v3ll v3uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v3coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)16, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Plot Devices") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/devices_plot_evolution_`name'.pdf", replace
	#delimit ;
	twoway
		(rcap v4ll v4uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v4coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)16, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Store or Plot Devices") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/devices_store_or_plot_evolution_`name'.pdf", replace

	* dwelled device plots
	#delimit ;
	twoway
		(rcap v5ll v5uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v5coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)16, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Dwelled Store Devices") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/dwelled_store_evolution_`name'.pdf", replace
	#delimit ;
	twoway
		(rcap v6ll v6uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v6coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)16, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Dwelled Plot Devices") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/dwelled_plot_evolution_`name'.pdf", replace
	#delimit ;
	twoway
		(rcap v7ll v7uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v7coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)16, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Dwelled Store or Plot Devices") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/dwelled_store_or_plot_evolution_`name'.pdf", replace
	
	* employees evolution plots
	#delimit ;
	twoway
		(rcap v8ll v8uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v8coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)16, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Employees") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/employees_evolution_`name'.pdf", replace
	#delimit ;
	twoway
		(rcap v9ll v9uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v9coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)16, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Store Traffic") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/traffic_store_evolution_`name'.pdf", replace
	
	* traffic plots
	#delimit ;
	twoway
		(rcap v10ll v10uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v10coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)16, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Plot Traffic") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/traffic_plot_evolution_`name'.pdf", replace
	#delimit ;
	twoway
		(rcap v11ll v11uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v11coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)16, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Store or Plot Traffic") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/traffic_store_or_plot_evolution_`name'.pdf", replace
	#delimit ;
	twoway
		(rcap v12ll v12uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v12coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)16, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Dwelled Store Traffic") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/tf_dwelled_store_evolution_`name'.pdf", replace
	#delimit ;
	twoway
		(rcap v13ll v13uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v13coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)16, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Dwelled Plot Traffic") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/tf_dwelled_plot_evolution_`name'.pdf", replace
	#delimit ;
	twoway
		(rcap v14ll v14uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v14coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)16, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Dwelled Store or Plot Traffic") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/tf_dwelled_store_or_plot_evolution_`name'.pdf", replace
	#delimit ;
	twoway
		(rcap v15ll v15uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
		(scatter v15coef week, m(o) mcolor($c1) yaxis(1))														
		, xlabel(-12(1)16, val angle(0) labsize(vsmall))
		yline(0, lcolor(black)) legend(off)								
		xtitle("Weeks")
		ytitle("Employee Traffic") $gpr
		ylabel(-0.2(0.1)0.2) graphregion(color(white));
	#delimit cr
	graph export "$figdir/traffic_employees_evolution_`name'.pdf", replace
	
}

/**************
	Heterogeneity Test 
	***************/	

*********************************************************************************
/* Split between MSA and Non-MSAs & Split between States */
*********************************************************************************

* merge with sod to get msa (full event window sample)
use "$datadir/source data/SOD/sodupdate2021", clear
drop if uninumbr == .
collapse (median) msabr (first) stalpbr, by(uninumbr)
tempfile crosswalk_sod_msa_st
save `crosswalk_sod_msa_st'
use "$datadir/temp_weekly_traffic_eventwindow.dta", clear
fmerge m:1 uninumbr using `crosswalk_sod_msa_st'
assert _merge != 1 
keep if _merge == 3
drop _merge 
gen MSA = "non_msa" if msabr == 0
replace MSA = "msa" if MSA == ""
save "$datadir/temp_weekly_traffic_eventwindow.dta", replace

* merge with sod to get msa (only the pair-matched event window sample)
use "$datadir/source data/SOD/sodupdate2021", clear
drop if uninumbr == .
collapse (median) msabr (first) stalpbr, by(uninumbr)
rename uninumbr key_uninumbr // as the pairwise regression tables have key_uninumbr and uninumbr
tempfile crosswalk_sod_msa_st
save `crosswalk_sod_msa_st'
use "$datadir/temp_weekly_traffic_matchedbr_eventwindow.dta", clear
merge m:1 key_uninumbr using `crosswalk_sod_msa_st'
assert _merge != 1 
keep if _merge == 3
drop _merge 
gen MSA = "non_msa" if msabr == 0
replace MSA = "msa" if MSA == ""
save "$datadir/temp_weekly_traffic_matchedbr_eventwindow", replace

*** functions to outpur regression tables for MSA vs Non-MSA results

capture program drop dynamic_regression
program define dynamic_regression
	args n 
	use "$datadir/temp_weekly_traffic_eventwindow.dta", clear
	if ("`n'" == "msa" | "`n'" == "non_msa") {
		keep if MSA == "`n'"
	}
	else {
		keep if stalpbr == "`n'"
	}
	foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot traffic_employees tf_* {
		if "`var'" == "devices_store" {
			reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store id_week) 
			outreg2 using "$tabdir/twfe_dynamic_`n'.xls", /// 
			title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)	
		}
		else {
			reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store id_week) 
			outreg2 using "$tabdir/twfe_dynamic_`n'.xls", /// 
			title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)
		}
	}

	foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot traffic_employees tf_* {
		if "`var'" == "devices_store" {
			reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store zip_week) 
			outreg2 using "$tabdir/twfe_dynamic_zipweek_`n'.xls", /// 
			title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)	
		}
		else {
			reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store zip_week) 
			outreg2 using "$tabdir/twfe_dynamic_zipweek_`n'.xls", /// 
			title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)
		}
	}

	use "$datadir/temp_weekly_traffic_matchedbr_eventwindow.dta", clear
	if ("`n'" == "msa" | "`n'" == "non_msa") {
		keep if MSA == "`n'"
	}
	else {
		keep if stalpbr == "`n'"
	}
	egen pair_week = group(pair id_week)
	foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot traffic_employees tf_*{
		if "`var'" == "devices_store" {
			reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store pair_week) 
			outreg2 using "$tabdir/twfe_dynamic_pairwise_`n'.xls", /// 
			title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
			bracket bdec(4) sdec(4) replace ///
			addtext(Branch FE, Yes, PairXWeek FE, Yes, Note: standard errors clustering at zip level)	
		}
		else {
			reghdfe `var' event_minus* event_plus*, vce(cl zip) absorb(id_store pair_week) 
			outreg2 using "$tabdir/twfe_dynamic_pairwise_`n'.xls", /// 
			title ("TWFE Estimator of Wells Fargo Scandal Effect") ctitle("`var'") ///
			bracket bdec(4) sdec(4) append ///
			addtext(Branch FE, Yes, PairXWeek FE, Yes, Note: standard errors clustering at zip level)
		}
	}
end

*********************************************************************************
/* Output Event-Study Figures */
*********************************************************************************

capture program drop dynamic_plots
program define dynamic_plots
	args n 
	foreach x in twfe_dynamic_`n' twfe_dynamic_zipweek_`n' twfe_dynamic_pairwise_`n' {
		import delimited "$tabdir/`x'.txt", clear

		// v2 - devices_store; v3 - devices_plot; v4 - devices_store_or_plot
		// v5 - dwelled_store; v6 - dwelled_plot; v7 - dwelled_store_or_plot
		// v8 - employees
		// v9 - traffic_store; v10 - traffic_plot; v11 - traffic_store_or_plot
		// v12 - tf_dwelled_store; v13 - tf_dwelled_store; v14 - tf_dwelled_store_or_plot
		// v15 - traffic_employees

		* check if the correct numbers are dropped
		drop in 1/4
		drop in 59/66
		replace v1 = "se_" +  v1[_n-1] if v1=="" & v1[_n-1]!=""
		forval i = 2/15  {
			replace v`i' = subinstr(v`i', "]", "",.) 
			replace v`i' = subinstr(v`i', "[", "",.) 
			replace v`i' = "" if v`i' == "-" 
			replace v`i' = subinstr(v`i', "*", "",.) 
		}	

		foreach v of varlist v2-v15 {
			destring `v', replace
			replace `v' = 0 if v1 == "Constant"
			replace `v' = 0 if v1 == "se_Constant"
		}

		egen week = seq(), from(-12) block(2)
		* note that constant is week 0, hence need to shift weeks after event +1
		replace week = week + 1 if week >= 0
		replace week = 0 if week == 17 // make constant to be the event date 
		replace v1 = "event" if v1 == "Constant"
		replace v1 = "se_event" if v1 == "se_Constant"
		replace v1 = substr(v1, 1, 2)
		reshape wide v2-v15, i(week) j(v1) string

		foreach v of numlist 2/15 {
			rename v`v'ev v`v'coef
			rename v`v'se v`v'se
			gen v`v'll = v`v'coef - v`v'se*1.96
			gen v`v'uu = v`v'coef + v`v'se*1.96
		}

		if "`x'" == "twfe_dynamic_`n'" local name "week_`n'" 
		if "`x'" == "twfe_dynamic_zipweek_`n'" local name "zipweek_`n'" 
		if "`x'" == "twfe_dynamic_pairwise_`n'" local name "pairwise_`n'" 
		* raw device plots
		#delimit ;
		twoway
			(rcap v2ll v2uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
			(scatter v2coef week, m(o) mcolor($c1) yaxis(1))														
			, xlabel(-12(1)16, val angle(0) labsize(vsmall))
			yline(0, lcolor(black)) legend(off)								
			xtitle("Weeks")
			ytitle("Store Devices") $gpr
			ylabel(-0.2(0.1)0.2) graphregion(color(white));
		#delimit cr
		graph export "$figdir/devices_store_evolution_`name'.pdf", replace
		#delimit ;
		twoway
			(rcap v3ll v3uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
			(scatter v3coef week, m(o) mcolor($c1) yaxis(1))														
			, xlabel(-12(1)16, val angle(0) labsize(vsmall))
			yline(0, lcolor(black)) legend(off)								
			xtitle("Weeks")
			ytitle("Plot Devices") $gpr
			ylabel(-0.2(0.1)0.2) graphregion(color(white));
		#delimit cr
		graph export "$figdir/devices_plot_evolution_`name'.pdf", replace
		#delimit ;
		twoway
			(rcap v4ll v4uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
			(scatter v4coef week, m(o) mcolor($c1) yaxis(1))														
			, xlabel(-12(1)16, val angle(0) labsize(vsmall))
			yline(0, lcolor(black)) legend(off)								
			xtitle("Weeks")
			ytitle("Store or Plot Devices") $gpr
			ylabel(-0.2(0.1)0.2) graphregion(color(white));
		#delimit cr
		graph export "$figdir/devices_store_or_plot_evolution_`name'.pdf", replace

		* dwelled device plots
		#delimit ;
		twoway
			(rcap v5ll v5uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
			(scatter v5coef week, m(o) mcolor($c1) yaxis(1))														
			, xlabel(-12(1)16, val angle(0) labsize(vsmall))
			yline(0, lcolor(black)) legend(off)								
			xtitle("Weeks")
			ytitle("Dwelled Store Devices") $gpr
			ylabel(-0.2(0.1)0.2) graphregion(color(white));
		#delimit cr
		graph export "$figdir/dwelled_store_evolution_`name'.pdf", replace
		#delimit ;
		twoway
			(rcap v6ll v6uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
			(scatter v6coef week, m(o) mcolor($c1) yaxis(1))														
			, xlabel(-12(1)16, val angle(0) labsize(vsmall))
			yline(0, lcolor(black)) legend(off)								
			xtitle("Weeks")
			ytitle("Dwelled Plot Devices") $gpr
			ylabel(-0.2(0.1)0.2) graphregion(color(white));
		#delimit cr
		graph export "$figdir/dwelled_plot_evolution_`name'.pdf", replace
		#delimit ;
		twoway
			(rcap v7ll v7uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
			(scatter v7coef week, m(o) mcolor($c1) yaxis(1))														
			, xlabel(-12(1)16, val angle(0) labsize(vsmall))
			yline(0, lcolor(black)) legend(off)								
			xtitle("Weeks")
			ytitle("Dwelled Store or Plot Devices") $gpr
			ylabel(-0.2(0.1)0.2) graphregion(color(white));
		#delimit cr
		graph export "$figdir/dwelled_store_or_plot_evolution_`name'.pdf", replace
		
		* employees evolution plots
		#delimit ;
		twoway
			(rcap v8ll v8uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
			(scatter v8coef week, m(o) mcolor($c1) yaxis(1))														
			, xlabel(-12(1)16, val angle(0) labsize(vsmall))
			yline(0, lcolor(black)) legend(off)								
			xtitle("Weeks")
			ytitle("Employees") $gpr
			ylabel(-0.2(0.1)0.2) graphregion(color(white));
		#delimit cr
		graph export "$figdir/employees_evolution_`name'.pdf", replace
		#delimit ;
		twoway
			(rcap v9ll v9uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
			(scatter v9coef week, m(o) mcolor($c1) yaxis(1))														
			, xlabel(-12(1)16, val angle(0) labsize(vsmall))
			yline(0, lcolor(black)) legend(off)								
			xtitle("Weeks")
			ytitle("Store Traffic") $gpr
			ylabel(-0.2(0.1)0.2) graphregion(color(white));
		#delimit cr
		graph export "$figdir/traffic_store_evolution_`name'.pdf", replace
		
		* traffic plots
		#delimit ;
		twoway
			(rcap v10ll v10uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
			(scatter v10coef week, m(o) mcolor($c1) yaxis(1))														
			, xlabel(-12(1)16, val angle(0) labsize(vsmall))
			yline(0, lcolor(black)) legend(off)								
			xtitle("Weeks")
			ytitle("Plot Traffic") $gpr
			ylabel(-0.2(0.1)0.2) graphregion(color(white));
		#delimit cr
		graph export "$figdir/traffic_plot_evolution_`name'.pdf", replace
		#delimit ;
		twoway
			(rcap v11ll v11uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
			(scatter v11coef week, m(o) mcolor($c1) yaxis(1))														
			, xlabel(-12(1)16, val angle(0) labsize(vsmall))
			yline(0, lcolor(black)) legend(off)								
			xtitle("Weeks")
			ytitle("Store or Plot Traffic") $gpr
			ylabel(-0.2(0.1)0.2) graphregion(color(white));
		#delimit cr
		graph export "$figdir/traffic_store_or_plot_evolution_`name'.pdf", replace
		#delimit ;
		twoway
			(rcap v12ll v12uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
			(scatter v12coef week, m(o) mcolor($c1) yaxis(1))														
			, xlabel(-12(1)16, val angle(0) labsize(vsmall))
			yline(0, lcolor(black)) legend(off)								
			xtitle("Weeks")
			ytitle("Dwelled Store Traffic") $gpr
			ylabel(-0.2(0.1)0.2) graphregion(color(white));
		#delimit cr
		graph export "$figdir/tf_dwelled_store_evolution_`name'.pdf", replace
		#delimit ;
		twoway
			(rcap v13ll v13uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
			(scatter v13coef week, m(o) mcolor($c1) yaxis(1))														
			, xlabel(-12(1)16, val angle(0) labsize(vsmall))
			yline(0, lcolor(black)) legend(off)								
			xtitle("Weeks")
			ytitle("Dwelled Plot Traffic") $gpr
			ylabel(-0.2(0.1)0.2) graphregion(color(white));
		#delimit cr
		graph export "$figdir/tf_dwelled_plot_evolution_`name'.pdf", replace
		#delimit ;
		twoway
			(rcap v14ll v14uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
			(scatter v14coef week, m(o) mcolor($c1) yaxis(1))														
			, xlabel(-12(1)16, val angle(0) labsize(vsmall))
			yline(0, lcolor(black)) legend(off)								
			xtitle("Weeks")
			ytitle("Dwelled Store or Plot Traffic") $gpr
			ylabel(-0.2(0.1)0.2) graphregion(color(white));
		#delimit cr
		graph export "$figdir/tf_dwelled_store_or_plot_evolution_`name'.pdf", replace
		#delimit ;
		twoway
			(rcap v15ll v15uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
			(scatter v15coef week, m(o) mcolor($c1) yaxis(1))														
			, xlabel(-12(1)16, val angle(0) labsize(vsmall))
			yline(0, lcolor(black)) legend(off)								
			xtitle("Weeks")
			ytitle("Employee Traffic") $gpr
			ylabel(-0.2(0.1)0.2) graphregion(color(white));
		#delimit cr
		graph export "$figdir/traffic_employees_evolution_`name'.pdf", replace
		
	}
end

dynamic_regression msa
dynamic_regression non_msa
dynamic_plots msa
dynamic_plots non_msa
* regressions with state names 
use "$datadir/temp_weekly_traffic_matchedbr_eventwindow.dta", clear
tab stalpbr 
// check states with too few observatiosn to drop them 
drop if stalpbr == "AK" | stalpbr == "AR" | stalpbr == "DE" | stalpbr == "HI" | ///
		stalpbr == "KS" | stalpbr == "MA" | stalpbr == "MS" | stalpbr == "NH" | ///
		stalpbr == "OH" | stalpbr == "RI" | stalpbr == "IL" | stalpbr == "IN" | ///
		stalpbr == "MI" | stalpbr == "MT" | stalpbr == "NM" | stalpbr == "WY"
levelsof stalpbr, clean local(stnames)

foreach state of local stnames {
	dynamic_regression `state'
	dynamic_plots `state'
}

*********************************************************************************
*********************************************************************************
*********************************************************************************
/* New Analysis Focusing on Traffic Changes after Bank Mergers */
*********************************************************************************
*********************************************************************************
*********************************************************************************

/**************
	Use Fed Data to Obtain M&A Cases from 2016 and onwards 
	***************/	
	
use "$datadir/source data/advan_sod_crosswalk.dta", clear
	* drop duplicates regarding id_store for now
	duplicates drop id_store, force // 90 obs deleted for now
	tempfile crosswalk
	save `crosswalk'
	
	* transition data from the website below, downloaded on Dec 6th, 2022
* https://www.ffiec.gov/npw/FinancialReport/DataDownload
import delimited "$datadir/source data/CSV_TRANSFORMATIONS.csv", clear

* generate acquisition date 
tostring dt_trans, replace
gen date = date(dt_trans, "YMD")
format date %td
gen week = week(date)
gen year = year(date)

gen week_date = yw(year, week)
format week_date %tw
* sample period from 2015w26 to 2022w26 (and require at least 12 months for the
* event study plots)
drop if week_date < yw(2015, 38) 
drop if week_date > yw(2022, 14)
tempfile mna
save `mna'
	
* change id_rssd_predecessor to rssdid to merge with sod data (we kept the earliest
* rssdid on SOD)
rename id_rssd_predecessor rssdid
* drop duplicates, only a few 
duplicates drop rssdid, force

merge 1:m rssdid using "`crosswalk'"

* keep only those id_store that underwent M&As during the sample period
keep if _merge == 3
drop _merge 
save "$datadir/source data/advan_sod_crosswalk_w_mna", replace

/**************
	Merge M&A Data to Cleaned Foot Traffic Data to Obtain M&A Timing 
	***************/	

use "$datadir/temp_weekly_traffic", clear

*** merge M&A data with the cleaned weekly traffic data
merge m:1 id_store using "$datadir/source data/advan_sod_crosswalk_w_mna", keepusing(date week_date)
* should get either matches or _merge == 1 (branches not undergoing M&A in the sample period)
drop if _merge == 2 // got one unmatched id_store (probably small error) it's ok
drop if _merge == 1 // drop those branches with banks not undergoing M&As in the sample period
drop _merge

*** obtain the event date for each merger in the data sample
* generate weekly_date for the panel 
drop date
rename week_date mna_date

gen week_date = yw(year, week)
format week_date %tw
* slight approximation (has to drop week == 53 instances) not a big deal
drop if week_date == .

*** now obtain event windows for mergers (take 12 weeks pre and 16 weeks post periods for
* any mergers)
gen event_day = week_date - mna_date
drop if event_day < -52
drop if event_day > 52

* generate dummies relative to mna week
forv i = 1/52 {
	bysort id_store (week_date): gen event_plus`i'weeks = 1 if event_day == `i' 
	replace event_plus`i'weeks = 0 if event_plus`i'weeks >=.
}

forv i = 1/52 {
	bysort id_store (week_date): gen event_minus`i'weeks = 1 if event_day == -`i'
	replace event_minus`i'weeks = 0 if event_minus`i'weeks >=.
}
drop event_week
gen event_week = 1 if event_day == 0
replace event_week = 0 if event_week >=.
save "$datadir/cleaned data/advan_mna_banks_traffic.dta", replace

/**************
	Output Figures Showing Traffic Change After M&As
	***************/	

*** simple time series figures for traffic before/after Mergers
use "$datadir/cleaned data/advan_mna_banks_traffic.dta", clear

collapse (mean) devices_* dwelled_* traffic_* tf_*, by(event_day)

tsset event_day
label var event_day "Weeks"

twoway (tsline devices_store) (tsline devices_plot) (tsline devices_store_or_plot), ///
graphregion(color(white)) legend(col(1))
graph export "$figdir/devices_evolution_mna.pdf", replace
twoway (tsline traffic_store) (tsline traffic_plot) (tsline traffic_store_or_plot), ///
graphregion(color(white)) legend(col(1))
graph export "$figdir/traffic_devices_evolution_mna.pdf", replace
*** dwelled traffic measures
twoway (tsline dwelled_store) (tsline dwelled_plot) (tsline dwelled_store_or_plot), ///
graphregion(color(white)) legend(col(1))
graph export "$figdir/dwelled_evolution_mna.pdf", replace
twoway (tsline tf_dwelled_store) (tsline tf_dwelled_plot) (tsline tf_dwelled_store_or_plot), ///
graphregion(color(white)) legend(col(1))
graph export "$figdir/traffic_dwelled_evolution_mna.pdf", replace


*** regressions to account for county and week FEs
use "$datadir/cleaned data/advan_mna_banks_traffic.dta", clear

foreach var of varlist devices_store devices_plot devices_store_or_plot dwelled_store dwelled_plot dwelled_store_or_plot employees traffic_store traffic_plot traffic_store_or_plot traffic_employees tf_* {
	reghdfe `var' event_minus* event_plus*, absorb(id_store) cluster(id_store)
	if "`var'" == "devices_store" {
		outreg2 using "$tabdir/mna_dynamic_evolution.xls", /// 
		title ("Mapping out Traffic Around M&As") ctitle("`var'") ///
		bracket bdec(4) sdec(4) replace ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)	
	}
	else {
		outreg2 using "$tabdir/mna_dynamic_evolution.xls", /// 
		title ("Mapping out Traffic Around M&As") ctitle("`var'") ///
		bracket bdec(4) sdec(4) append ///
		addtext(Branch FE, Yes, Week FE, Yes, Note: standard errors clustering at zip level)
	}
}

*** output mapped-out event study style figures

import delimited "$tabdir/mna_dynamic_evolution.txt", clear

// v2 - devices_store; v3 - devices_plot; v4 - devices_store_or_plot
// v5 - dwelled_store; v6 - dwelled_plot; v7 - dwelled_store_or_plot
// v8 - employees
// v9 - traffic_store; v10 - traffic_plot; v11 - traffic_store_or_plot
// v12 - tf_dwelled_store; v13 - tf_dwelled_store; v14 - tf_dwelled_store_or_plot
// v15 - traffic_employees

* check if the correct numbers are dropped
drop in 1/4
drop in 59/66
replace v1 = "se_" +  v1[_n-1] if v1=="" & v1[_n-1]!=""
forval i = 2/15  {
	replace v`i' = subinstr(v`i', "]", "",.) 
	replace v`i' = subinstr(v`i', "[", "",.) 
	replace v`i' = "" if v`i' == "-" 
	replace v`i' = subinstr(v`i', "*", "",.) 
}	

foreach v of varlist v2-v15 {
	destring `v', replace
	replace `v' = 0 if v1 == "Constant"
	replace `v' = 0 if v1 == "se_Constant"
}

egen week = seq(), from(-12) block(2)
* note that constant is week 0, hence need to shift weeks after event +1
replace week = week + 1 if week >= 0
replace week = 0 if week == 17 // make constant to be the event date 
replace v1 = "event" if v1 == "Constant"
replace v1 = "se_event" if v1 == "se_Constant"
replace v1 = substr(v1, 1, 2)
reshape wide v2-v15, i(week) j(v1) string

foreach v of numlist 2/15 {
	rename v`v'ev v`v'coef
	rename v`v'se v`v'se
	gen v`v'll = v`v'coef - v`v'se*1.96
	gen v`v'uu = v`v'coef + v`v'se*1.96
}

* raw device plots
#delimit ;
twoway
	(rcap v2ll v2uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
	(scatter v2coef week, m(o) mcolor($c1) yaxis(1))														
	, xlabel(-12(1)16, val angle(0) labsize(vsmall))
	yline(0, lcolor(black)) legend(off)								
	xtitle("Weeks")
	ytitle("Store Devices") $gpr
	ylabel(-0.2(0.1)0.2) graphregion(color(white));
#delimit cr
graph export "$figdir/devices_store_mna_dynamic_evolution.pdf", replace
#delimit ;
twoway
	(rcap v3ll v3uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
	(scatter v3coef week, m(o) mcolor($c1) yaxis(1))														
	, xlabel(-12(1)16, val angle(0) labsize(vsmall))
	yline(0, lcolor(black)) legend(off)								
	xtitle("Weeks")
	ytitle("Plot Devices") $gpr
	ylabel(-0.2(0.1)0.2) graphregion(color(white));
#delimit cr
graph export "$figdir/devices_plot_mna_dynamic_evolution.pdf", replace
#delimit ;
twoway
	(rcap v4ll v4uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
	(scatter v4coef week, m(o) mcolor($c1) yaxis(1))														
	, xlabel(-12(1)16, val angle(0) labsize(vsmall))
	yline(0, lcolor(black)) legend(off)								
	xtitle("Weeks")
	ytitle("Store or Plot Devices") $gpr
	ylabel(-0.2(0.1)0.2) graphregion(color(white));
#delimit cr
graph export "$figdir/devices_store_or_plot_mna_dynamic_evolution.pdf", replace

* dwelled device plots
#delimit ;
twoway
	(rcap v5ll v5uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
	(scatter v5coef week, m(o) mcolor($c1) yaxis(1))														
	, xlabel(-12(1)16, val angle(0) labsize(vsmall))
	yline(0, lcolor(black)) legend(off)								
	xtitle("Weeks")
	ytitle("Dwelled Store Devices") $gpr
	ylabel(-0.2(0.1)0.2) graphregion(color(white));
#delimit cr
graph export "$figdir/dwelled_store_mna_dynamic_evolution.pdf", replace
#delimit ;
twoway
	(rcap v6ll v6uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
	(scatter v6coef week, m(o) mcolor($c1) yaxis(1))														
	, xlabel(-12(1)16, val angle(0) labsize(vsmall))
	yline(0, lcolor(black)) legend(off)								
	xtitle("Weeks")
	ytitle("Dwelled Plot Devices") $gpr
	ylabel(-0.2(0.1)0.2) graphregion(color(white));
#delimit cr
graph export "$figdir/dwelled_plot_mna_dynamic_evolution.pdf", replace
#delimit ;
twoway
	(rcap v7ll v7uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
	(scatter v7coef week, m(o) mcolor($c1) yaxis(1))														
	, xlabel(-12(1)16, val angle(0) labsize(vsmall))
	yline(0, lcolor(black)) legend(off)								
	xtitle("Weeks")
	ytitle("Dwelled Store or Plot Devices") $gpr
	ylabel(-0.2(0.1)0.2) graphregion(color(white));
#delimit cr
graph export "$figdir/dwelled_store_or_plot_mna_dynamic_evolution.pdf", replace

* employees evolution plots
#delimit ;
twoway
	(rcap v8ll v8uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
	(scatter v8coef week, m(o) mcolor($c1) yaxis(1))														
	, xlabel(-12(1)16, val angle(0) labsize(vsmall))
	yline(0, lcolor(black)) legend(off)								
	xtitle("Weeks")
	ytitle("Employees") $gpr
	ylabel(-0.2(0.1)0.2) graphregion(color(white));
#delimit cr
graph export "$figdir/employees_mna_dynamic_evolution.pdf", replace
#delimit ;
twoway
	(rcap v9ll v9uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
	(scatter v9coef week, m(o) mcolor($c1) yaxis(1))														
	, xlabel(-12(1)16, val angle(0) labsize(vsmall))
	yline(0, lcolor(black)) legend(off)								
	xtitle("Weeks")
	ytitle("Store Traffic") $gpr
	ylabel(-0.2(0.1)0.2) graphregion(color(white));
#delimit cr
graph export "$figdir/traffic_store_mna_dynamic_evolution.pdf", replace

* traffic plots
#delimit ;
twoway
	(rcap v10ll v10uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
	(scatter v10coef week, m(o) mcolor($c1) yaxis(1))														
	, xlabel(-12(1)16, val angle(0) labsize(vsmall))
	yline(0, lcolor(black)) legend(off)								
	xtitle("Weeks")
	ytitle("Plot Traffic") $gpr
	ylabel(-0.2(0.1)0.2) graphregion(color(white));
#delimit cr
graph export "$figdir/traffic_plot_mna_dynamic_evolution.pdf", replace
#delimit ;
twoway
	(rcap v11ll v11uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
	(scatter v11coef week, m(o) mcolor($c1) yaxis(1))														
	, xlabel(-12(1)16, val angle(0) labsize(vsmall))
	yline(0, lcolor(black)) legend(off)								
	xtitle("Weeks")
	ytitle("Store or Plot Traffic") $gpr
	ylabel(-0.2(0.1)0.2) graphregion(color(white));
#delimit cr
graph export "$figdir/traffic_store_or_plot_mna_dynamic_evolution.pdf", replace
#delimit ;
twoway
	(rcap v12ll v12uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
	(scatter v12coef week, m(o) mcolor($c1) yaxis(1))														
	, xlabel(-12(1)16, val angle(0) labsize(vsmall))
	yline(0, lcolor(black)) legend(off)								
	xtitle("Weeks")
	ytitle("Dwelled Store Traffic") $gpr
	ylabel(-0.2(0.1)0.2) graphregion(color(white));
#delimit cr
graph export "$figdir/tf_dwelled_store_mna_dynamic_evolution.pdf", replace
#delimit ;
twoway
	(rcap v13ll v13uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
	(scatter v13coef week, m(o) mcolor($c1) yaxis(1))														
	, xlabel(-12(1)16, val angle(0) labsize(vsmall))
	yline(0, lcolor(black)) legend(off)								
	xtitle("Weeks")
	ytitle("Dwelled Plot Traffic") $gpr
	ylabel(-0.2(0.1)0.2) graphregion(color(white));
#delimit cr
graph export "$figdir/tf_dwelled_plot_mna_dynamic_evolution.pdf", replace
#delimit ;
twoway
	(rcap v14ll v14uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
	(scatter v14coef week, m(o) mcolor($c1) yaxis(1))														
	, xlabel(-12(1)16, val angle(0) labsize(vsmall))
	yline(0, lcolor(black)) legend(off)								
	xtitle("Weeks")
	ytitle("Dwelled Store or Plot Traffic") $gpr
	ylabel(-0.2(0.1)0.2) graphregion(color(white));
#delimit cr
graph export "$figdir/tf_dwelled_store_or_plot_mna_dynamic_evolution.pdf", replace
#delimit ;
twoway
	(rcap v15ll v15uu week, lcolor($c1) lw(thin) lp(dash) yaxis(1))										
	(scatter v15coef week, m(o) mcolor($c1) yaxis(1))														
	, xlabel(-12(1)16, val angle(0) labsize(vsmall))
	yline(0, lcolor(black)) legend(off)								
	xtitle("Weeks")
	ytitle("Employee Traffic") $gpr
	ylabel(-0.2(0.1)0.2) graphregion(color(white));
#delimit cr
graph export "$figdir/traffic_employees_mna_dynamic_evolution.pdf", replace
	
********************************************************************************
capture log close
exit
