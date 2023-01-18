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
dir <-paste0("/Users/",Sys.info()['user'],"/Dropbox (Chicago Booth)/Bank Foot Traffic/data/source data/advan/t2/history/")

outdir<-paste0("/Users/",Sys.info()['user'],"/Dropbox (Chicago Booth)/Bank Foot Traffic/data/cleaned data/")
setwd(dir)

#========================================================================
#                   Step 1: Load Advan Raw Data
#------------------------------------------------------------------------

advan_files <- Sys.glob("*.csv")
advan_files <- sub("_Vxv.*", "", advan_files)
advan_files <- sub(".*t2_", "", advan_files)
ticker <- unique(advan_files)

for (t in ticker) {
  advan_files <- Sys.glob(paste0("t2_", t, "_Vxv", "*.csv"))
  
  data_list<-lapply(advan_files, function(x) fread(x))
  DT<-rbindlist(data_list, use.names = TRUE, fill = TRUE)
  # get year and quarter for collapsing (average within ID_store and year/quarter)
  DT[, year := year(day)]
  DT[, week := week(day)]
  # choose apps for data (either all (not choosing), C01, or SDK2)
  # DT<-DT[app == "ALLD"]
  # collapse the data down to weekly levels using variables available
  variables <- c("devices_store", "devices_plot", "devices_store_or_plot", 
                 "dwelled_store", "dwelled_plot", "dwelled_store_or_plot",
                 "devices", "devices_50", "employees")
  DT<-DT[, c('id_store', 'year', 'week', variables), with = FALSE]
  setnafill(DT, fill = 0)   # need to fill NAs by 0 in order to compute the mean of traffic (sometimes Advan data records zero traffic with missing)
  dt <- DT[, lapply(.SD, mean), by=. (id_store, year, week), .SDcols = variables]
  write.csv(dt, paste0(outdir, paste0("Data_", t, ".csv")), row.names = FALSE)
  rm(dt, DT, data_list, advan_files)
  gc() 
}

# advan_files <- Sys.glob("*BBT*.csv")
# data_list<-lapply(advan_files, function(x) fread(x))
# DT<-rbindlist(data_list, use.names = TRUE, fill = TRUE)
# # get year and quarter for collapsing (average within ID_store and year/quarter)
# DT[, year := year(day)]
# DT[, week := week(day)]
# # collapse the data down to weekly levels using variables available
# variables <- c("devices_store", "devices_plot", "devices_store_or_plot", 
#                "dwelled_store", "dwelled_plot", "dwelled_store_or_plot",
#                "devices", "devices_50")
# dt <- DT[, lapply(.SD, mean), by=. (id_store, year, week), .SDcols = variables]
# write.csv(dt, paste0(outdir, paste0("Data_", "BAC", ".csv")), row.names = FALSE)
# rm(list = ls())
# gc() 

# merge together the cleaned csv files and save to stata dta. file
setwd(outdir)
cleaned_files <- Sys.glob("*.csv")
data_list<-lapply(cleaned_files, function(x) fread(x))
DT<-rbindlist(data_list, use.names = TRUE, fill = TRUE)
write_dta(DT, paste0(outdir, "weekly_advan_traffic_updated20221004.dta"))
  
