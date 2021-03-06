#Script used to upload the scores of analyzed bills
#Standard Environment cleansing
rm(list=ls())
#Include shared header
source("~/379SeniorProject/r_dp/shared.R")
#Connect to processing database and close connection on exit
library(RMySQL)
con <- dbConnect(RMySQL::MySQL(),group="data-processing")
#Will use filepath specified in command line arguments or will use:
filename = '~/BulkData/bill_scores.csv'

#Parse command line arguments to get filepath of bill scores
args = commandArgs(trailingOnly=TRUE)
if(length(args) > 0){
  filename = args[1]
}

#Read bill scores into dataframe for processing
bill_scores <- read.table(filename, header=TRUE, sep=",", quote="|", comment.char='#', stringsAsFactors=FALSE)
bill_upload_data <- data.frame()

#For each issue name ensure there is a matching issue in the database and get it's id
issue_names <- colnames(bill_scores)
if(issue_names[1] != "id"){
  stop("First entry in issues table should be bill's id")
}
id_numbers <- c(-1)
for(i in 2:length(issue_names)){
  result <- dbGetQuery(con, paste("SELECT * FROM ",ISSUE_TBL," WHERE issue_shortname=\"", gsub("."," ",issue_names[i], fixed = TRUE),"\"", sep=""))
  if(length(result$Id) == 0){
    stop("bill score header not found in database")  
  }
  id_numbers[i] <- as.integer(result$Id)
  bill_upload_data[i-1,'issue_name'] <- issue_names[i]
  bill_upload_data[i-1,'bill_count'] <- 0
}

#Uploads the scores of a bill for each issue
bill_score_upload <- function(count){
  scores_frame = data.frame("bill_id"=character(), "issue_id"=numeric(), "score"=numeric(), stringsAsFactors=FALSE)
  for(i in 2:length(id_numbers)){
    scores_frame[i-1,"bill_id"] <- bill_scores[count,"id"]
    scores_frame[i-1,"issue_id"] <- id_numbers[i]
    scores_frame[i-1,"score"] <- bill_scores[count, i]
    if(bill_scores[count, i] != 0){
      bill_upload_data[id_numbers[i],'bill_count'] <<- bill_upload_data[id_numbers[i],'bill_count'] + 1
    }
  }
  ignore <- dbWriteTable(conn=con, name=BILL_SCORE_TBL, value=scores_frame, row.names = FALSE, overwrite = FALSE, append = TRUE)
  rm(scores_frame)
  progress(count, 2*n_bills_scored)
}

#For every bill insert it's scores
ignore <- dbRemoveTable(conn=con, name=BILL_SCORE_TBL)
n_bills_scored <- nrow(bill_scores)
status(paste("Uploading scores from ",n_bills_scored," bills"))
dp_log(paste("Parsing scores from ",n_bills_scored," bills"))
ignore <- sapply(1:n_bills_scored, bill_score_upload)

for(i in 1:nrow(bill_upload_data)){
  dp_log(paste("Issue ",bill_upload_data[i,'issue_name'], " : ",bill_upload_data[i,'bill_count']," bills uploaded"))
}

#Delete all bills that are not analyzed to allow for faster scoring
ignore <- dbSendStatement(con, paste( 
  "DELETE FROM ",BILL_TBL," 
  WHERE vote_id NOT IN 
	  ( SELECT bill_id
	  FROM ",BILL_SCORE_TBL,");",sep=""))
progress(75,100)
#Delete all votes for bills that are not analyzed to allow for faster scoring
ignore <- dbSendStatement(con, paste(
  "DELETE FROM ",VOTE_TBL,"
  WHERE bill_id NOT IN 
	  ( SELECT vote_id
	  FROM ",BILL_TBL," );",sep=""))
progress(100,100)

ignore <- dbDisconnect(con)