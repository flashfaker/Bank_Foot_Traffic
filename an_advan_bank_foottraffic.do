* create crosswalk between advan foot traffic data store_id and sod branch id
local fname an_advan_bank_foottraffic

******************************* SYNOPSIS ***************************************
/* 
Purpose: Analyze the cleaned weekly foot traffic data of 82 banks from Advan

Author: Zirui Song
Date Created: Jul 21st, 2022
Date Modified: Aug 3rd, 2022

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
		duplicates drop id_store, force // 97 obs deleted for now
		tempfile crosswalk 
		save `crosswalk'

	use "$datadir/cleaned data/weekly_advan_traffic", clear
	fmerge m:1 id_store using "`crosswalk'"
	keep if _merge == 3
	drop _merge
	save "$datadir/cleaned data/weekly_advan_traffic_mergedbanks", replace
	
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
	
*** simple linear regression models 
	
	
********************************************************************************
capture log close
exit
