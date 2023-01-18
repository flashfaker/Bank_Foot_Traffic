* create crosswalk between advan foot traffic data store_id and sod branch id
local fname cr_advan_sod_crosswalk

******************************* SYNOPSIS ***************************************
/* 


Author: Zirui Song
Date Created: Jul 14th, 2022
Date Modified: Jan 4th, 2022

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
	global datadir = "$repodir/data/source data"
	global figdir = "$repodir/output/figures/zs"
	
	* Start plain text log file with same name
	log using "$logdir/`fname'.txt", replace text

/**************
	Clean Data
	***************/
	
	use "$datadir/SOD/sodupdate2021.dta", clear
* first drop all years prior to 2015 as Advan data only from 2015-2022
	gsort year
	drop if year < 2015
	
* check uninumbr (unique location for each branch (regardless of M&As)
	gsort uninumbr
	
* drop duplicates and also keep only variables useful for matching
	keep rssdid uninumbr-zipbr city2br sims_latitude sims_longitude namehcr 
	* make sure lat and long are not missing
	drop if sims_latitude == . | sims_longitude == .s
	gduplicates drop 
	* keep the first ones
	bysort uninumbr: keep if _n == 1
	save "$datadir/SOD/sod_branch_location", replace

	* the chunk below only applies to mapping when we haven't received store information 
	* on bank names from Advan ---
	/*
*** clean bank ticker mapping
	import excel "$datadir/SOD/Bank_Ticker_Mapping.xlsx", clear
	keep B C 
	rename (B C) (bank_name ticker_mother_company)
	tempfile ticker_map
	save `ticker_map'
	
	import delimited "$repodir/advan/t2/stores_vXV.csv", clear
* keep only US ones 
	keep if country_code == "US"
	
	* split the strings s.t. we have only the mother company for bank tickers
	split ticker, parse("-") limit(1) gen(ticker_mother_company)
	rename ticker_mother_company1 ticker_mother_company
	 
	merge m:1 ticker_mother_company using "`ticker_map'"
		* manually check and put in bank names for those that are not matched 
		tab ticker if _merge == 1
		tab ticker_mother_company if _merge == 1
		replace bank_name = "BB&T Corporation" if ticker == "BBT"
		replace bank_name = "Beacon Bancorp" if ticker == "BEACON-A-BCSB"
		replace bank_name = "BNP Paribas SA" if ticker == "BNPQF-BW"
		replace bank_name = "Carolina Financial Corporation" if ticker == "CARO-CRESCOM"
		replace bank_name = "Cornerstone Bancorp" if ticker == "CNBP"
		replace bank_name = "Fidelity Bank" if ticker == "FIDEL-A" 
		replace bank_name = "F&M Bank Corp" if ticker_mother_company == "FMBM"
		replace bank_name = "Keycorp" if ticker == "FNFG"
		replace bank_name = "Gorham Savings Bank" if ticker == "GORHAM-A"
		replace bank_name = "HSBC Holdings plc" if ticker == "HBCYF"
		replace bank_name = "John Marshall Bancorp" if ticker == "JMSB"
		replace bank_name = "Mascoma Bank" if ticker == "MASCOMA-A"
		replace bank_name = "Ozark Bank" if ticker == "OZRK"
		replace bank_name = "Banco Santander SA" if ticker == "SAN"
		replace bank_name = "Suntruct Banks, Inc." if ticker == "STI"
		replace bank_name = "Toronto-Dominion Bank" if ticker == "TD"
		replace bank_name = "TSB Bank" if ticker == "TSB-A"

	drop _merge 
	drop if bank_name == ""
		*/	
		
	* using store information sent by Advan to obtain bank names (more accurate)
	import delimited "$datadir/advan/t2/stores_info.csv", clear
		tempfile store_name
		save `store_name'
	import delimited "$datadir/advan/t2/stores_vXV.csv", clear
	merge 1:1 id_store using `store_name', keepusing(company_name dba)
	
/*	unmatched from master mainly due to foreign banks (only 3 are not)
    Result                      Number of obs
    -----------------------------------------
    Not matched                         7,489
        from master                     7,184  (_merge==1)
        from using                        305  (_merge==2)

    Matched                            48,648  (_merge==3)
    -----------------------------------------
*/
	keep if _merge == 3
	drop _merge
	rename company_name bank_name
	
	* save as intermediate to investigate matching rates later on
	save "$datadir/advan/t2/stores.dta", replace
/**************
	Matching Step
	***************/

*** 1. joinby zip code (to generate all possible pairings within a zip code)
	* drop the strings with .0 at the end or zipcodes with form xxxxx-xxxx
	replace zip = substr(zip, 1, strlen(zip)-2) if substr(zip, -2, 2) == ".0"
	replace zip = substr(zip, 1, strlen(zip)-5) if substr(zip, -5, 1) == "-"
	rename zip zipbr
	destring zipbr, replace
	* keep only useful variables
	keep id_store store_lat store_lon address city state zipbr bank_name dba
	joinby zipbr using "$datadir/SOD/sod_branch_location"
	
*** order and sort variables for better view
	gsort zipbr id_store
	order zipbr id_store uninumbr bank_name namehcr store_lat store_lon sims_latitude sims_longitude address addresbr city citybr state stalpbr
	
	* drop those that are not in the same cities (wrongly recorded zip codes for PR)
	* and longitude, latitude really far apart
	gen lat_diff = abs(store_lat-sims_latitude) 
	gen long_diff = abs(store_lon-sims_longitude)
	drop if (state != stalpbr) | lat_diff > 0.5 | long_diff > 0.5
	
*** exact matches of address
	* clean up the address abbreviations
	* gen rid of dots in address
	
	foreach x in address addresbr {
		replace `x' = subinstr(`x', ".", "", .)
		replace `x' = subinstr(`x', " + ", " ", .)
		replace `x' = subinstr(`x', "Avenue", "Av", 1)
		replace `x' = subinstr(`x', "Ave", "Av", 1)
		replace `x' = subinstr(`x', "Road", "Rd", 1) 
		replace `x' = subinstr(`x', "Drive", "Dr", 1)
		replace `x' = subinstr(`x', "Place", "Pl", 1)
		replace `x' = subinstr(`x', "Boulevard", "Blvd", 1)
		replace `x' = subinstr(`x', "Route", "Rt", 1)
		replace `x' = subinstr(`x', "Highway", "Hwy", 1)
		replace `x' = subinstr(`x', "Street", "St", 1)
		replace `x' = subinstr(`x', "Suite", "Ste", 1)
		replace `x' = subinstr(`x', "Court", "CT", 1)
		replace `x' = subinstr(`x', "Circle", "CIR", 1)
		replace `x' = subinstr(`x', "Plaza", "Plz", 1)
		replace `x' = subinstr(`x', "Lane", "Ln", 1)
		replace `x' = subinstr(`x', "Parkway", "Pkwy", 1)
		replace `x' = subinstr(`x', "Floor", "Fl", 1)
		replace `x' = subinstr(`x', "Turnpike", "Tpke", 1)
		replace `x' = subinstr(`x', "Trail", "Tr", 1)
		* replace the North, South, West, East (direction ones
		replace `x' = subinstr(`x', " N ", " North ", 1)
		replace `x' = subinstr(`x', " S ", " South ", 1)
		replace `x' = subinstr(`x', " W ", " West ", 1)
		replace `x' = subinstr(`x', " E ", " East ", 1)
		replace `x' = subinstr(`x', " N", " North", 1) if substr(`x', -2, 2) == " N"
		replace `x' = subinstr(`x', " S", " South", 1) if substr(`x', -2, 2) == " S"
		replace `x' = subinstr(`x', " W", " West", 1) if substr(`x', -2, 2) == " W"
		replace `x' = subinstr(`x', " E", " East", 1) if substr(`x', -2, 2) == " E"
		* replace numbers (first-tenth)
		replace `x' = subinstr(`x', "Fisrt", "1st", 1)
		replace `x' = subinstr(`x', "Second", "2nd", 1)
		replace `x' = subinstr(`x', "Third", "3rd", 1)
		replace `x' = subinstr(`x', "Fourth", "4th", 1)	
		replace `x' = subinstr(`x', "Fifth", "5th", 1)
		replace `x' = subinstr(`x', "Sixth", "6th", 1)	
		replace `x' = subinstr(`x', "Seventh", "7th", 1)
		replace `x' = subinstr(`x', "Eighth", "8th", 1)	
		replace `x' = subinstr(`x', "Ninth", "9th", 1)	
		replace `x' = subinstr(`x', "Tenth", "10th", 1)
		replace `x' = subinstr(`x', "One", "1", 1)
		replace `x' = subinstr(`x', "Two", "2", 1)
		replace `x' = subinstr(`x', "Three", "3", 1)	
		replace `x' = subinstr(`x', "Four", "4", 1)	
		replace `x' = subinstr(`x', "Five", "5", 1)	
		replace `x' = subinstr(`x', "Six", "6", 1)	
		replace `x' = subinstr(`x', "Seven", "7", 1)	
		replace `x' = subinstr(`x', "Eight", "8", 1)	
		replace `x' = subinstr(`x', "Nine", "9", 1)	
		replace `x' = subinstr(`x', "Ten", "10", 1)	
	}

	* change all strings to lowercase
	foreach str in address addresbr bank_name dba namehcr namefull {
		replace `str' = strlower(`str')
	}
	
	gen exact = 1 if address == addresbr
		
	* keep those that have been exactly matched in a tempfile 
	preserve
		keep if exact == 1
		*** note that the exact matches have duplicates (one id_store matched to multiple branches)
		replace namefull = subinstr(namefull, ", national association", "", .)	
		ustrdist bank_name namehcr, gen(banknamedist1)
		ustrdist bank_name namefull, gen(banknamedist2)
		ustrdist dba namehcr, gen(banknamedist3)
		ustrdist dba namefull, gen(banknamedist4)
		egen bankname_dist = rowmin(banknamedist1 banknamedist2 banknamedist3 banknamedist4)
		drop banknamedist*
		* within exact exactly matched address, keep only the one branch that has the closest name to the bank_name in case of duplicates (in case where there is no duplicates, the name different is ok as there are mergers and acquisitions and change of local branch name sometimes)
		bysort id_store (bankname_dist): egen bankname_dist_min = min(bankname_dist)
		keep if bankname_dist_min == bankname_dist
		* do the same for each unique uninumbr as well
		drop bankname_dist_min
		bysort uninumbr (bankname_dist): egen bankname_dist_min = min(bankname_dist)
		keep if bankname_dist_min == bankname_dist
		tempfile exact
		save `exact', replace
	restore
	* and drop the id_stores that have been exactly matched
	bysort id_store: egen exact_matched = max(exact) 
	sum lat_diff long_diff if exact == 1 // get a sense of how close (lat-long) the exact matches are 
	drop if exact_matched == 1
	
*** fuzzy matches based on distances
	ustrdist address addresbr, gen(addresdist)
	gsort zipbr id_store addresdist
	order addresdist address addresbr bank_name namehcr namefull *_diff
	
	* keep only Levenstein distances smaller than 10 ones 
	drop if addresdist > 10 
	
	/* 1. within each zip-id_store combinations, first keep the ones with Levenstein distances <= 2 
	gen fuzzy_dist_1 = 1 if addresdist == 1
	* save the above data 
	preserve
		keep if fuzzy_dist_1 == 1
		tempfile fuzzy_dist_1
		save `fuzzy_dist_1', replace
	restore
	* and drop the id_stores that have been exactly matched
	bysort id_store: egen fuzzy_dist_1_matched = max(fuzzy_dist_1) 
	sum lat_diff long_diff if fuzzy_dist_1 == 1 // get a sense of how close the fuzzy dist 1 matches are 
	drop if fuzzy_dist_1_matched == 1
	*/
	// note that for the exact matches, the lat-long differences are around 0.0015 

	* 1. get string distances between bank_name (advan) and namehcr/namefull (SOD)
		replace namefull = subinstr(namefull, ", national association", "", .)	
		ustrdist bank_name namehcr, gen(banknamedist1)
		ustrdist bank_name namefull, gen(banknamedist2)
		ustrdist dba namehcr, gen(banknamedist3)
		ustrdist dba namefull, gen(banknamedist4)
		egen bankname_dist = rowmin(banknamedist1 banknamedist2 banknamedist3 banknamedist4)
		drop banknamedist*
		* manually check for a threshold that shows that bank names are the same
		gsort zipbr id_store bankname_dist
		* also keep only the closest bank names for each unique store 
		bysort id_store (bankname_dist): keep if _n == 1
		drop if bankname_dist > 5		
	
	* 2. now check the lat-long coordinates and addresses to see if we have good matches	
		drop if addresdist > 5
		drop if lat_diff > 0.001 | long_diff > 0.001 // here we are really conservative as there are also pretty good matchings if we take lat/long_diff to be around 0.002. 
		gen fuzzy = 1 

*** merge exact and fuzzy match results together
	append using "`exact'"
	
	* order and keep variables (keep rssdid to find bank M&As)
	keep rssdid bank_name name* address addresbr zipbr id_store uninumbr store_lat store_lon sims_* city state exact fuzzy 
	replace exact = 0 if exact >=.
	replace fuzzy = 0 if fuzzy >=.
	
	order id_store uninumbr	
		
	save "$datadir/advan_sod_crosswalk_dup", replace
	* within each duplicated match from uninumbr to id_store, keep only the exact matched ones
	bysort uninumbr (exact): keep if _n == 1
	* note that there are still a few duplicates due to duplicated unibranch 
	duplicates tag id_store, gen(dup)
	tab dup  
	* but looking over the duplicates shows that id_store is correctly matched
	* to each branch --
	
save "$datadir/advan_sod_crosswalk", replace

/**************
	Histograms
	***************/
	
*** matching rates of banks in the Advan sample already
	use "$datadir/advan_sod_crosswalk", clear
	duplicates drop id_store, force
	merge 1:1 id_store using "$datadir/advan/t2/stores.dta"
	replace bank_name = strlower(bank_name)
	egen matched = rowmax(exact fuzzy)
	bysort bank_name: egen match_total = sum(matched)
	bysort bank_name: gen match_rate = match_total / _N
	* keep only those with matched total > 10 for plot
	* keep if match_total > 10
	* plot
	graph hbar match_rate, over(bank_name, sort(1) descending label(labsize(*0.3))) ytitle("Match Rate of Banks from Advan Sample") graphregion(color(white))
	graph export "$figdir/advan_match_rate.pdf", replace
	graph hbar match_total, over(bank_name, sort(1) descending label(labsize(*0.3))) ytitle("Total Matched Branches from Advan Sample") graphregion(color(white))
	graph export "$figdir/advan_match_total.pdf", replace
	
*** matching rates of banks from the SOD data
	use "$datadir/advan_sod_crosswalk", clear
	merge 1:1 uninumbr using "$datadir/SOD/sod_branch_location"
	* standardize the newly merged full name of banks
	replace namefull = strlower(namefull)
	replace namefull = subinstr(namefull, ", national association", "", .)	
	egen matched = rowmax(exact fuzzy)
	bysort namefull: egen match_total = sum(matched)
	bysort namefull: gen match_rate = match_total / _N
	* keep only those that have at least positive match rates 
	drop if match_rate == 0
	* keep only those with matched total > 15 for plot
	keep if match_total > 15
	* plot
	graph hbar match_rate, over(namefull, sort(1) descending label(labsize(*0.30))) ytitle("Match Rate of Banks from SOD (only those with more than 15 matches)") graphregion(color(white))
	graph export "$figdir/sod_match_rate.pdf", replace
	graph hbar match_total, over(namefull, sort(1) descending label(labsize(*0.30))) ytitle("Total Matched Branches from SOD (only those with more than 15 matches)") graphregion(color(white))
	graph export "$figdir/sod_match_total.pdf", replace
	
*** get unmatched sample for inspection 
	use "$datadir/advan_sod_crosswalk_dup", clear
	duplicates drop id_store, force
	merge 1:1 id_store using "$datadir/advan/t2/stores.dta"
	keep if _merge == 2
	drop _merge 
	keep id_store address bank_name store_* city state ticker-country_code dba
	save "$datadir/unmatched_advan_branches.dta", replace
	
/**************
	Try to match unmatched sample (matching on city first)
	***************/
	use "$datadir/unmatched_advan_branches.dta", clear

*** 1. joinby city (to generate all possible pairings within a zip code)
	rename city citybr
	keep id_store store_lat store_lon address citybr state zip bank_name dba
	joinby citybr using "$datadir/SOD/sod_branch_location"
	
*** order and sort variables for better view
	gsort citybr id_store
	order citybr id_store uninumbr bank_name namehcr store_lat store_lon sims_latitude sims_longitude address addresbr zip zipbr state stalpbr
	
	* drop those that are not in the same cities (wrongly recorded zip codes for PR)
	* and longitude, latitude really far apart
	gen lat_diff = abs(store_lat-sims_latitude) 
	gen long_diff = abs(store_lon-sims_longitude)
	drop if (state != stalpbr) | lat_diff > 0.5 | long_diff > 0.5
	
*** exact matches of address
	* clean up the address abbreviations
	* gen rid of dots in address
	
	foreach x in address addresbr {
		replace `x' = subinstr(`x', ".", "", .)
		replace `x' = subinstr(`x', " + ", " ", .)
		replace `x' = subinstr(`x', "Avenue", "Av", 1)
		replace `x' = subinstr(`x', "Ave", "Av", 1)
		replace `x' = subinstr(`x', "Road", "Rd", 1) 
		replace `x' = subinstr(`x', "Drive", "Dr", 1)
		replace `x' = subinstr(`x', "Place", "Pl", 1)
		replace `x' = subinstr(`x', "Boulevard", "Blvd", 1)
		replace `x' = subinstr(`x', "Route", "Rt", 1)
		replace `x' = subinstr(`x', "Highway", "Hwy", 1)
		replace `x' = subinstr(`x', "Street", "St", 1)
		replace `x' = subinstr(`x', "Suite", "Ste", 1)
		replace `x' = subinstr(`x', "Court", "CT", 1)
		replace `x' = subinstr(`x', "Circle", "CIR", 1)
		replace `x' = subinstr(`x', "Plaza", "Plz", 1)
		replace `x' = subinstr(`x', "Lane", "Ln", 1)
		replace `x' = subinstr(`x', "Parkway", "Pkwy", 1)
		replace `x' = subinstr(`x', "Floor", "Fl", 1)
		replace `x' = subinstr(`x', "Turnpike", "Tpke", 1)
		replace `x' = subinstr(`x', "Trail", "Tr", 1)
		replace `x' = subinstr(`x', "Square", "Sq", 1)
		* replace the North, South, West, East (direction ones
		replace `x' = subinstr(`x', " N ", " North ", 1)
		replace `x' = subinstr(`x', " S ", " South ", 1)
		replace `x' = subinstr(`x', " W ", " West ", 1)
		replace `x' = subinstr(`x', " E ", " East ", 1)
		replace `x' = subinstr(`x', " N", " North", 1) if substr(`x', -2, 2) == " N"
		replace `x' = subinstr(`x', " S", " South", 1) if substr(`x', -2, 2) == " S"
		replace `x' = subinstr(`x', " W", " West", 1) if substr(`x', -2, 2) == " W"
		replace `x' = subinstr(`x', " E", " East", 1) if substr(`x', -2, 2) == " E"
		* replace numbers (first-tenth)
		replace `x' = subinstr(`x', "Fisrt", "1st", 1)
		replace `x' = subinstr(`x', "Second", "2nd", 1)
		replace `x' = subinstr(`x', "Third", "3rd", 1)
		replace `x' = subinstr(`x', "Fourth", "4th", 1)	
		replace `x' = subinstr(`x', "Fifth", "5th", 1)
		replace `x' = subinstr(`x', "Sixth", "6th", 1)	
		replace `x' = subinstr(`x', "Seventh", "7th", 1)
		replace `x' = subinstr(`x', "Eighth", "8th", 1)	
		replace `x' = subinstr(`x', "Ninth", "9th", 1)	
		replace `x' = subinstr(`x', "Tenth", "10th", 1)
		replace `x' = subinstr(`x', "One", "1", 1)
		replace `x' = subinstr(`x', "Two", "2", 1)
		replace `x' = subinstr(`x', "Three", "3", 1)	
		replace `x' = subinstr(`x', "Four", "4", 1)	
		replace `x' = subinstr(`x', "Five", "5", 1)	
		replace `x' = subinstr(`x', "Six", "6", 1)	
		replace `x' = subinstr(`x', "Seven", "7", 1)	
		replace `x' = subinstr(`x', "Eight", "8", 1)	
		replace `x' = subinstr(`x', "Nine", "9", 1)	
		replace `x' = subinstr(`x', "Ten", "10", 1)	
	}

	* change all strings to lowercase
	foreach str in address addresbr bank_name dba namehcr namefull {
		replace `str' = strlower(`str')
	}
	
	gen exact = 1 if address == addresbr
		
	* keep those that have been exactly matched in a tempfile 
	preserve
		keep if exact == 1
		*** note that the exact matches have duplicates (one id_store matched to multiple branches)
		replace namefull = subinstr(namefull, ", national association", "", .)	
		ustrdist bank_name namehcr, gen(banknamedist1)
		ustrdist bank_name namefull, gen(banknamedist2)
		ustrdist dba namehcr, gen(banknamedist3)
		ustrdist dba namefull, gen(banknamedist4)
		egen bankname_dist = rowmin(banknamedist1 banknamedist2 banknamedist3 banknamedist4)
		drop banknamedist*
		* within exact exactly matched address, keep only the one branch that has the closest name to the bank_name in case of duplicates (in case where there is no duplicates, the name different is ok as there are mergers and acquisitions and change of local branch name sometimes)
		bysort id_store (bankname_dist): egen bankname_dist_min = min(bankname_dist)
		keep if bankname_dist_min == bankname_dist
		* do the same for each unique uninumbr as well
		drop bankname_dist_min
		bysort uninumbr (bankname_dist): egen bankname_dist_min = min(bankname_dist)
		keep if bankname_dist_min == bankname_dist
		tempfile exact_city
		save `exact_city', replace
	restore
	* and drop the id_stores that have been exactly matched
	bysort id_store: egen exact_matched = max(exact) 
	sum lat_diff long_diff if exact == 1 // get a sense of how close (lat-long) the exact matches are 
	drop if exact_matched == 1	
	
*** fuzzy matches based on distances
	ustrdist address addresbr, gen(addresdist)
	gsort citybr id_store addresdist
	order addresdist address addresbr bank_name namehcr namefull *_diff
	
	* keep only Levenstein distances smaller than 10 ones 
	drop if addresdist > 10 
	
	// note that for the exact matches, the lat-long differences are around 0.0022 and 0.0031

	* 1. get string distances between bank_name (advan) and namehcr/namefull (SOD)
		replace namefull = subinstr(namefull, ", national association", "", .)	
		ustrdist bank_name namehcr, gen(banknamedist1)
		ustrdist bank_name namefull, gen(banknamedist2)
		ustrdist dba namehcr, gen(banknamedist3)
		ustrdist dba namefull, gen(banknamedist4)
		egen bankname_dist = rowmin(banknamedist1 banknamedist2 banknamedist3 banknamedist4)
		drop banknamedist*
		* manually check for a threshold that shows that bank names are the same
		gsort citybr id_store bankname_dist
		* also keep only the closest bank names for each unique store 
		bysort id_store (bankname_dist): keep if _n == 1
		drop if bankname_dist > 5		
	
	* 2. now check the lat-long coordinates and addresses to see if we have good matches	
		order id_store uninumbr zip zipbr *_diff
		
		drop if addresdist > 3
		drop if lat_diff > 0.002 | long_diff > 0.002 // here we are really conservative as there are also pretty good matchings if we take lat/long_diff to be around 0.002. 
		gen fuzzy = 1 
		
*** merge exact and fuzzy match results together
	append using "`exact_city'"
	
	* order and keep variables 
	keep bank_name name* address addresbr zipbr id_store uninumbr store_lat store_lon sims_* citybr state exact fuzzy 
	replace exact = 0 if exact >=.
	replace fuzzy = 0 if fuzzy >=.
	
	order id_store uninumbr	
		
	save "$datadir/advan_sod_crosswalk_city", replace
	* within each duplicated match from uninumbr to id_store, keep only the exact matched ones
	bysort uninumbr (exact): keep if _n == 1
	* note that there are still a few duplicates due to duplicated unibranch 
	duplicates tag id_store, gen(dup)
	tab dup  
	* but looking over the duplicates shows that id_store is correctly matched
	* to each branch --
	
	append using "$datadir/advan_sod_crosswalk"
	save "$datadir/advan_sod_crosswalk_full", replace
	
*** get unmatched sample after having matched on zip and city for merge
	use "$datadir/advan_sod_crosswalk_full", clear
	duplicates drop id_store, force
	merge 1:1 id_store using "$datadir/advan/t2/stores.dta"
	keep if _merge == 2
	drop _merge 
	keep id_store address bank_name store_* city state ticker-country_code dba
	save "$datadir/unmatched_advan_branches.dta", replace
********************************************************************************
capture log close
exit
