##########################################################################################################
#AIM: Code to import and clean Advan Foot Traffic Data for US Major Banks
#  - 

# SOURCE FOR CODE: "Dropbox (Chicago Booth)\Bank Foot Traffic\Code\cr_advan_bank_foottraffic.R"

# SOURCE FOR DATA: 
# - "Dropbox (Chicago Booth)\Bank Foot Traffic\advan\t2\history"
##########################################################################################################

rm(list = ls())

#Install required packaged (if not already installed)
check.packages <- function(pkg){
  new.pkg <- pkg[!(pkg %in% installed.packages()[, "Package"])]
  if (length(new.pkg)) 
    install.packages(new.pkg, dependencies = TRUE)
  sapply(pkg, require, character.only = TRUE)
}
packages<-c("data.table","haven","stringr","stringdist","kableExtra","readr")
check.packages(packages)

`%notin%` <- Negate(`%in%`)

#Define Directories 
###### (Note that Windows requires "C:/Users/" instead)
dir <-paste0("/Users/",Sys.info()['user'],"/Dropbox (Chicago Booth)/Bank Foot Traffic/advan/t2/history")

outdir<-paste0("/Users/",Sys.info()['user'],"/Dropbox (Chicago Booth)/Bank Foot Traffic/cleaned data")
setwd(dir)

#========================================================================
#                   Step 1: Load Advan Raw Data
#------------------------------------------------------------------------
ticker <- c("BAC", "BBT", "BEACON_A_BCSB", "BHB", "BNPQF_BW", "BNPQF", "BPRN", "BRKL", "BXS", "C_BMX")

for (t in ticker) {
  bac_files <- Sys.glob("*t*.csv")
  
  data_list<-lapply(bac_files, function(x) fread(x))
  DT<-rbindlist(data_list, use.names = TRUE, fill = TRUE)
  # get year and quarter for collapsing (average within ID_store and year/quarter)
  DT[, year := year(day)]
  DT[, week := week(day)]
  # collapse the data down to quarterly levels using variables available
  variables <- c("devices_store", "devices_plot", "devices_store_or_plot", 
                 "dwelled_store", "dwelled_plot", "dwelled_store_or_plot",
                 "devices", "devices_50")
  paste0("Data_", t) <- DT[, lapply(.SD, mean), by=. (id_store, year, week), .SDcols = variables]
  rm(DT, data_list)
  gc() 
}
