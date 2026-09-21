-- =============================================================================
-- BigQuery DDL: 8 ACSM Core Tables (T1–T8) in Project `trustedtesterarvind`
-- Auto-generated with 100% Table & Column Descriptions from `Mock Metadata.xlsx`
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS `trustedtesterarvind.acsm_bronze`
OPTIONS (description = "AEON Credit Service Malaysia (ACSM) — 8 Core Tables (T1-T8) with Governed Metadata");

LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T1_Fact_EP_Judge` (
  `Rcd_DT` STRING OPTIONS(description = "Data extraction date"),
  `CIF_NO` FLOAT64 OPTIONS(description = "Unique customer ID"),
  `APPL_NO` STRING OPTIONS(description = "PRODUCT application number"),
  `AGREE_NO` FLOAT64 OPTIONS(description = "PRODUCT loan account number"),
  `APPL_DT` FLOAT64 OPTIONS(description = "Easy payment application date"),
  `APPL_STS` STRING OPTIONS(description = "Easy payment application status"),
  `JUDGE_DT` FLOAT64 OPTIONS(description = "Easy payment application decision date"),
  `SCORING_POINT` FLOAT64 OPTIONS(description = "Easy payment Final Score for decision"),
  `SCORING_TYPE` FLOAT64 OPTIONS(description = "Easy payment Final Score type"),
  `SCORING_RANK` STRING OPTIONS(description = "Easy payment Final score rank based on bucket"),
  `LOAN_CODE` STRING OPTIONS(description = "Loan type"),
  `LOAN_TYP_ID` STRING OPTIONS(description = "Loan subtype"),
  `LOAN_GRP` STRING OPTIONS(description = "Loan group"),
  `AGENT_CODE1` STRING OPTIONS(description = "Merchant group"),
  `AGENT_CODE2` STRING OPTIONS(description = "Merchant subgroup"),
  `APPL_CHANNEL` STRING OPTIONS(description = "Application channel"),
  `REJECT_CODE` STRING OPTIONS(description = "Reject Code"),
  `FIN_AMT` FLOAT64 OPTIONS(description = "Easy payment finance approved amount"),
  `FIN_PRFT_AMT` FLOAT64 OPTIONS(description = "Easy payment profit/interest amount"),
  `FIN_TOTAL_AMT` FLOAT64 OPTIONS(description = "Easy payment financing total amount"),
  `INST_AMT` FLOAT64 OPTIONS(description = "Easy payment installment amount"),
  `DEPOSIT` FLOAT64 OPTIONS(description = "% for downpayment"),
  `INTEREST` FLOAT64 OPTIONS(description = "Easy payment interest"),
  `TOTAL_INST` FLOAT64 OPTIONS(description = "Easy payment total installment months; loan tenure"),
  `JointIncome_FG` STRING OPTIONS(description = "Joint income yes/no flag"),
  `SCORE_DECISION` STRING OPTIONS(description = "Easy payment score decision: accept/decline"),
  `NetIncome` FLOAT64 OPTIONS(description = "Easy payment applicant net income"),
  `Income` FLOAT64 OPTIONS(description = "Easy payment applicant income"),
  `Age` INT64 OPTIONS(description = "Easy payment applicant age"),
  `HomeYear` FLOAT64 OPTIONS(description = "Number of years living in current residence"),
  `YearOfBusiness` FLOAT64 OPTIONS(description = "Number of years of employment in current company"),
  `AnnualIncome` FLOAT64 OPTIONS(description = "Annual income"),
  `TOTAL_AEON_INST` FLOAT64 OPTIONS(description = "Total installment for all Aeon products"),
  `TOTAL_AEON_OSB` FLOAT64 OPTIONS(description = "Total outstanding balance for all Aeon products"),
  `CUR_REPAY_RATIO` FLOAT64 OPTIONS(description = "Current repayment ratio"),
  `NEW_REPAY_RATIO` FLOAT64 OPTIONS(description = "New repayment ratio"),
  `NDI` FLOAT64 OPTIONS(description = "Net disposable income"),
  `CUR_DSR` FLOAT64 OPTIONS(description = "Current debt to service ratio"),
  `NEW_DSR` FLOAT64 OPTIONS(description = "New debt to service ratio"),
  `B_OtherIncome` FLOAT64 OPTIONS(description = "Other income"),
  `B_NonBankCommitment` FLOAT64 OPTIONS(description = "Non-bank commitment"),
  `DEPENDANT` FLOAT64 OPTIONS(description = "Children, spouse."),
  `YEAR_MADE` STRING OPTIONS(description = "Easy payment vehicle year made"),
  `NOB` STRING OPTIONS(description = "Nature of Business"),
  `HomeOwner_flag` STRING OPTIONS(description = "Ownership check of home"),
  `CIFState` STRING OPTIONS(description = "Customer address state as at application"),
  `Race` STRING OPTIONS(description = "Customer race as at application"),
  `Gender` STRING OPTIONS(description = "Customer gender as at application"),
  `Marital` STRING OPTIONS(description = "Customer marital status as at application"),
  `National` STRING OPTIONS(description = "Customer nationality as at application"),
  `Occupation` STRING OPTIONS(description = "Customer occupation as at application"),
  `Academic` STRING OPTIONS(description = "Customer academic qualification as at application"),
  `B_AdvInstallPymt` FLOAT64 OPTIONS(description = "Easy payment advanced install payment"),
  `AdvInstallPymtBand` STRING OPTIONS(description = "Easy payment advanced installment payment band"),
  `JudgeWeek_FG` STRING OPTIONS(description = "Judge week flag"),
  `Biometric_FG` STRING OPTIONS(description = "Biometric indicator"),
  `E-KYC` STRING OPTIONS(description = "E-KYC pass/fail"),
  `OTP` STRING OPTIONS(description = "OTP pass/fail"),
  `APPLY_FIN_AMT` FLOAT64 OPTIONS(description = "Easy payment applied financing amount"),
  `PreAssessment_Flag` STRING OPTIONS(description = "Some customers qualify for pre-assessment")
)
OPTIONS(
  description = "The current (daily full refreshed) application status (Approved or Rejected) for EP products. (Governed via Mock Metadata.xlsx | Sheet: T1 - Fact_EP_Judge)"
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T1_Fact_EP_Judge.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T2_Fact_EP_Sales` (
  `TX_DT` FLOAT64 OPTIONS(description = "Sales Date"),
  `CIF_No` STRING OPTIONS(description = "Unique customer ID"),
  `TransactionCountry` STRING OPTIONS(description = "Ringgit Malaysia"),
  `TransactionCountryHigherLevel` STRING OPTIONS(description = "Local or Oversea"),
  `PriviledgeMerchantsGrp` STRING OPTIONS(description = "Member merchant"),
  `LDESC` STRING OPTIONS(description = "Spend Location"),
  `Sales_Type` STRING OPTIONS(description = "Cash Purchase or Cash Advance"),
  `Amount` FLOAT64 OPTIONS(description = "Transaction Amount"),
  `TransCount` FLOAT64 OPTIONS(description = "Transaction Count")
)
OPTIONS(
  description = "The confirmed sales log of the EP product. (Governed via Mock Metadata.xlsx | Sheet: T2 - Fact_EP_Sales)"
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T2_Fact_EP_Sales.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T3_Fact_EP_Collection` (
  `TX_DT` FLOAT64 OPTIONS(description = "Reporting date"),
  `First_INST_DT` FLOAT64 OPTIONS(description = "First intallment date"),
  `Agree_No` STRING OPTIONS(description = "Loan agreement ID"),
  `CIF_No` STRING OPTIONS(description = "Unique customer ID"),
  `Current_Time_Payment` STRING OPTIONS(description = "current installment period"),
  `Del_Sts` STRING OPTIONS(description = "Lock Deliquency status"),
  `Collection_Branch` STRING OPTIONS(description = "Branch ID"),
  `Score_Value` FLOAT64 OPTIONS(description = "Collection Score Point"),
  `Score_Grade` STRING OPTIONS(description = "Collection Score Grade"),
  `Sub_Code` STRING OPTIONS(description = "AKPK checker"),
  `Pay_in_Full` STRING OPTIONS(description = "Account Status"),
  `Classification_Code` STRING OPTIONS(description = "Life Deliquency status"),
  `FinPlus_Code` STRING OPTIONS(description = "FinPlus (e-credit evaluation) tier"),
  `MDD` STRING OPTIONS(description = "EP Multi Due Date"),
  `LoanTyp_ID` STRING OPTIONS(description = "Loan product type indicator"),
  `Billing_OSP` FLOAT64 OPTIONS(description = "Principal Billing amount"),
  `Billing_Count` FLOAT64 OPTIONS(description = "Principal Billing count"),
  `Collection_OSP` FLOAT64 OPTIONS(description = "Principal Collection amount"),
  `Collection_Count` FLOAT64 OPTIONS(description = "Principal Collection count"),
  `Unpaid_OSP` FLOAT64 OPTIONS(description = "Principal Unpaid amount"),
  `Unpaid_Count` FLOAT64 OPTIONS(description = "Principal Unpaid count")
)
OPTIONS(
  description = "The collection status snapshot for EP products as at closing period (Governed via Mock Metadata.xlsx | Sheet: T3 - Fact_EP_Collection)"
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T3_Fact_EP_Collection.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T4_Fact_CC_Judge` (
  `Rcd_DT` STRING OPTIONS(description = "Data extraction date"),
  `Account_No` STRING OPTIONS(description = "Card account number"),
  `Appl_ID` STRING OPTIONS(description = "Credit card application ID"),
  `ApplSts_ID` STRING OPTIONS(description = "Credit card application status ID"),
  `CIF_ID` STRING OPTIONS(description = "Credit card customer ID"),
  `CardTyp_ID` STRING OPTIONS(description = "Credit card type"),
  `CardBrand_ID` STRING OPTIONS(description = "Credit card brand"),
  `CardApplTyp_ID` STRING OPTIONS(description = "Principal/supplementary"),
  `ApplChnnl_ID` STRING OPTIONS(description = "Credit card application channel"),
  `Reject_ID` STRING OPTIONS(description = "Credit card rejection reason ID"),
  `Decline_ID` STRING OPTIONS(description = "Rejection reason"),
  `Agent_ID` STRING OPTIONS(description = "Merchant ID"),
  `ScoreDecision_ID` STRING OPTIONS(description = "Credit card score decision category"),
  `ScoreRank_ID` STRING OPTIONS(description = "Credit card score rank"),
  `SysRcmmd_ID` STRING OPTIONS(description = "System recommended decision"),
  `Gender` STRING OPTIONS(description = "Gender"),
  `Age` INT64 OPTIONS(description = "Age"),
  `Race` STRING OPTIONS(description = "Race"),
  `Nationality` STRING OPTIONS(description = "Nationality short code"),
  `MaritalSts` STRING OPTIONS(description = "Marital Status"),
  `Academic` STRING OPTIONS(description = "Highest academic qualification"),
  `YrStay` INT64 OPTIONS(description = "Number of years living in current residence"),
  `HomeOwn` STRING OPTIONS(description = "Type of home ownership"),
  `Occupation` STRING OPTIONS(description = "Occupation"),
  `NOB` STRING OPTIONS(description = "Nature of business of customers employer"),
  `YrJob` INT64 OPTIONS(description = "Year in job"),
  `NetIncome` INT64 OPTIONS(description = "Net income"),
  `GrossIncome` INT64 OPTIONS(description = "Gross income"),
  `AnnualIncome` INT64 OPTIONS(description = "Annual income"),
  `AnnualIncomeTotLmt` INT64 OPTIONS(description = "Annual income total limit"),
  `CurrRepay` INT64 OPTIONS(description = "Current repayment amount"),
  `NewRepay` INT64 OPTIONS(description = "New repayment amount"),
  `RcmmdIntrst` FLOAT64 OPTIONS(description = "Recommended interest rate"),
  `NDI` INT64 OPTIONS(description = "Net Disposable Income"),
  `CurrDSR` FLOAT64 OPTIONS(description = "Current DSR"),
  `NewDSR` FLOAT64 OPTIONS(description = "New DSR"),
  `PaySlipTyp_ID` STRING OPTIONS(description = "Payslip type"),
  `CardActivate_FG` STRING OPTIONS(description = "Card activated"),
  `EmergencyCont_FG` STRING OPTIONS(description = "Emergency contact provided"),
  `CardActivate_DT` FLOAT64 OPTIONS(description = "Card activation date"),
  `Judge_DT` FLOAT64 OPTIONS(description = "Decision date"),
  `Appl_DT` FLOAT64 OPTIONS(description = "Application date"),
  `B_Limit` FLOAT64 OPTIONS(description = "Total limit"),
  `B_CrLimit` FLOAT64 OPTIONS(description = "Credit limit"),
  `B_CashAdvLimit` FLOAT64 OPTIONS(description = "Cash advance limit"),
  `B_NonBankCommitment` FLOAT64 OPTIONS(description = "Non bank commitment"),
  `CIFState_ID` STRING OPTIONS(description = "State"),
  `Biometric_FG` STRING OPTIONS(description = "Biometric indicator"),
  `FinalDecline_ID` STRING OPTIONS(description = "Decline ID"),
  `Final_Score` FLOAT64 OPTIONS(description = "Credit card CTOS score"),
  `Final_Score_Type` FLOAT64 OPTIONS(description = "Credit card CTOS score"),
  `Final_ScoreDesc` STRING OPTIONS(description = "Credit card CTOS score description"),
  `ApplyCardBiz_ID` STRING OPTIONS(description = "Applied card ID"),
  `ProposedCardBiz_ID` STRING OPTIONS(description = "Proposed card ID")
)
OPTIONS(
  description = "The current (daily full refreshed) application status (Approved or Rejected) for credit cards. (Governed via Mock Metadata.xlsx | Sheet: T4 - Fact_CC_Judge)"
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T4_Fact_CC_Judge_v2.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T5_Fact_CC_Sales` (
  `TX_DT` FLOAT64 OPTIONS(description = "Sales Date"),
  `CIF_No` STRING OPTIONS(description = "Unique customer ID"),
  `TransactionCountry` STRING OPTIONS(description = "Ringgit Malaysia"),
  `TransactionCountryHigherLevel` STRING OPTIONS(description = "Local or Oversea"),
  `PriviledgeMerchantsGrp` STRING OPTIONS(description = "Member merchant"),
  `LDESC` STRING OPTIONS(description = "Spend Location"),
  `Sales_Type` STRING OPTIONS(description = "Cash Purchase or Cash Advance"),
  `Amount` FLOAT64 OPTIONS(description = "Transaction Amount"),
  `TransCount` FLOAT64 OPTIONS(description = "Transaction Count")
)
OPTIONS(
  description = "The actual spending & cash advance log on credit card (Governed via Mock Metadata.xlsx | Sheet: T5 - Fact_CC_Sales)"
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T5_Fact_CC_Sales.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T6_Fact_CC_Collection` (
  `TX_DT` FLOAT64 OPTIONS(description = "Reporting date"),
  `Account_No` STRING OPTIONS(description = "CC account ID"),
  `CIF_No` STRING OPTIONS(description = "Unique customer ID"),
  `DC_Sts` STRING OPTIONS(description = "Lock deliquency status"),
  `Application_Branch` STRING OPTIONS(description = "Branch ID"),
  `Score_Value` FLOAT64 OPTIONS(description = "Collection Score point"),
  `Score_Grade` STRING OPTIONS(description = "Collection Score grade"),
  `MDD` STRING OPTIONS(description = "CC Due Date"),
  `FinPlus_Code` STRING OPTIONS(description = "FinPlus (e-credit evaluation) tier"),
  `Billing_OSP` FLOAT64 OPTIONS(description = "Billing amount"),
  `Billing_Count` FLOAT64 OPTIONS(description = "Billing count"),
  `Collection_OSP` FLOAT64 OPTIONS(description = "Collection amount"),
  `Collection_Count` FLOAT64 OPTIONS(description = "Collection count"),
  `Unpaid_OSP` FLOAT64 OPTIONS(description = "Unpaid amount"),
  `Unpaid_Count` FLOAT64 OPTIONS(description = "Unpaid count"),
  `Maintain_OSP` FLOAT64 OPTIONS(description = "Maintain amount"),
  `Maintain_Count` FLOAT64 OPTIONS(description = "Maintain count")
)
OPTIONS(
  description = "The billing and collection status snapshot for credit cards as at closing period (Governed via Mock Metadata.xlsx | Sheet: T6 - Fact_CC_Collection)"
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T6_Fact_CC_Collection.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T7_m3CIF` (
  `Rcd_DT` STRING OPTIONS(description = "Record refresh date"),
  `CIF_ID` STRING OPTIONS(description = "Customer ID"),
  `CIF_NM` STRING OPTIONS(description = "Customer name"),
  `CIF_NM1` STRING OPTIONS(description = "Customer name"),
  `CIF_NM2` STRING OPTIONS(description = "Customer name"),
  `MaritalSts` STRING OPTIONS(description = "MaritalStatus"),
  `Gender` STRING OPTIONS(description = "Gender"),
  `Citizen` STRING OPTIONS(description = "Citizen"),
  `State` STRING OPTIONS(description = "State"),
  `Region` STRING OPTIONS(description = "Region"),
  `Race` STRING OPTIONS(description = "Race"),
  `NOB` STRING OPTIONS(description = "Nature of business"),
  `HomeOwn` STRING OPTIONS(description = "Customer's homeowner category"),
  `HomePost` STRING OPTIONS(description = "Customer's home postcode"),
  `_HomeAddr1` STRING OPTIONS(description = "_HomeAddr1"),
  `_HomeAddr2` STRING OPTIONS(description = "_HomeAddr2"),
  `_HomeAddr3` STRING OPTIONS(description = "_HomeAddr3"),
  `EmpPost` STRING OPTIONS(description = "Employment Postal Code"),
  `MailPost` STRING OPTIONS(description = "Mail Postal Code"),
  `Occupation` STRING OPTIONS(description = "Occupation"),
  `PayslipTyp` STRING OPTIONS(description = "PayslipTyp"),
  `Academic` STRING OPTIONS(description = "Academic qualifications"),
  `Emp_NM` STRING OPTIONS(description = "Employer Name"),
  `SelftEmp_FG` STRING OPTIONS(description = "Self Employment Indicator"),
  `Felda_FG` STRING OPTIONS(description = "Felda is a government program to help rural Malaysians."),
  `JoinIncome_FG` STRING OPTIONS(description = "Joint Income Indicator"),
  `RecvPromo_FG` STRING OPTIONS(description = "Received promotion indicator"),
  `N_Age` FLOAT64 OPTIONS(description = "Age"),
  `N_YrStay` FLOAT64 OPTIONS(description = "Number of years living in current residence"),
  `N_YrJob` FLOAT64 OPTIONS(description = "Number of years in current job"),
  `B_NetIncome` FLOAT64 OPTIONS(description = "Net Income"),
  `B_GrossIncome` FLOAT64 OPTIONS(description = "Gross Income"),
  `B_AnnualIncome` FLOAT64 OPTIONS(description = "Annual Income"),
  `EmpSts` INT64 OPTIONS(description = "Employment Status")
)
OPTIONS(
  description = "Customer latest status daily refresh table (Governed via Mock Metadata.xlsx | Sheet: T7 - m3CIF)"
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T7_m3CIF.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);

LOAD DATA OVERWRITE `trustedtesterarvind.acsm_bronze.T8_dimProduct` (
  `Expiry_DT` STRING OPTIONS(description = "Card expiry date"),
  `FirstSpend_DT` STRING OPTIONS(description = "First spend date"),
  `Block_Code` STRING OPTIONS(description = "If card is blocked"),
  `Block_Date` FLOAT64 OPTIONS(description = "If card is blocked"),
  `CIC_Status` STRING OPTIONS(description = "CIC status"),
  `Card_Status` STRING OPTIONS(description = "Card status"),
  `AKPK_Status` STRING OPTIONS(description = "AKPK status"),
  `Card_First_Emboss_Date` FLOAT64 OPTIONS(description = "Physical card issuance date"),
  `Card_Emboss_Date` FLOAT64 OPTIONS(description = "Card emboss date"),
  `Card_First_Activated_Date` FLOAT64 OPTIONS(description = "Card first activated date"),
  `Card_Activated_Date` FLOAT64 OPTIONS(description = "Card current activated date"),
  `CP_CL` FLOAT64 OPTIONS(description = "Credit Purchase Total Limit"),
  `CP_CL_Available` FLOAT64 OPTIONS(description = "Credit Purchase Available Limit"),
  `CA_CL` FLOAT64 OPTIONS(description = "Credit Advance Total Limit"),
  `CA_CL_Available` FLOAT64 OPTIONS(description = "Credit Advance Available Limit"),
  `CP_CL_Usage` FLOAT64 OPTIONS(description = "Credit Purchase Usage"),
  `CA_CL_Usage` FLOAT64 OPTIONS(description = "Credit Advance Usage"),
  `CIF_ID` STRING OPTIONS(description = "Unique customer ID"),
  `Account_No` FLOAT64 OPTIONS(description = "Card account number"),
  `Account_Agree_Sts` STRING OPTIONS(description = "Account agreement status"),
  `Virtual_Card_Flag` STRING OPTIONS(description = "Virtual card indicator"),
  `Wallet_Tier` STRING OPTIONS(description = "Loyalty account Tier")
)
OPTIONS(
  description = "The current and daily full refresh master record of all active cards (Governed via Mock Metadata.xlsx | Sheet: T8 - dimProduct)"
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://acsm-workshop-landing-trustedtesterarvind/full_compressed/T8_dimProduct.csv.gz'],
  skip_leading_rows = 1,
  allow_quoted_newlines = TRUE
);
