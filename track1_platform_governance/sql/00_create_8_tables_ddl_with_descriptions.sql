-- =============================================================================
-- Create All 8 ACSM Base Tables in `acsm_bronze` with Table & Column Descriptions
-- Project: `<PROJECT_ID>` (e.g. `${PROJECT_ID}`) | Dataset: `acsm_bronze`
-- Location: `asia-southeast1` (Singapore)
-- Source Dictionary: `Mock Metadata.xlsx` (8 tables: Fact_EP_Judge, Fact_EP_Sales, Fact_EP_Collection, Fact_CC_Judge, Fact_CC_Sales, Fact_CC_Collection, m3CIF, dimProduct | 241 described columns)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS `acsm_bronze`
OPTIONS (
  location = "asia-southeast1",
  description = "AEON Credit Service Malaysia (ACSM) — 8 Core Tables (T1-T8) with Governed Metadata (Singapore Region)"
);

BEGIN
  DROP VIEW IF EXISTS `acsm_bronze.m3CIF`;
EXCEPTION WHEN ERROR THEN
  SELECT @@error.message;
END;

BEGIN
  DROP VIEW IF EXISTS `acsm_bronze.dimProduct`;
EXCEPTION WHEN ERROR THEN
  SELECT @@error.message;
END;

CREATE OR REPLACE TABLE `acsm_bronze.Fact_EP_Judge` (
  `Rcd_DT` DATE OPTIONS(description = "Data extraction date [Source Data Type: date]"),
  `CIF_NO` INT64 OPTIONS(description = "Unique customer ID [Source Data Type: numeric]"),
  `APPL_NO` INT64 OPTIONS(description = "PRODUCT application number [Source Data Type: varchar]"),
  `AGREE_NO` INT64 OPTIONS(description = "PRODUCT loan account number [Source Data Type: numeric]"),
  `APPL_DT` INT64 OPTIONS(description = "Easy payment application date [Source Data Type: numeric]"),
  `APPL_STS` STRING OPTIONS(description = "Easy payment application status [Source Data Type: varchar]"),
  `JUDGE_DT` INT64 OPTIONS(description = "Easy payment application decision date [Source Data Type: numeric]"),
  `SCORING_POINT` INT64 OPTIONS(description = "Easy payment Final Score for decision [Source Data Type: numeric]"),
  `SCORING_TYPE` INT64 OPTIONS(description = "Easy payment Final Score type [Source Data Type: numeric]"),
  `SCORING_RANK` STRING OPTIONS(description = "Easy payment Final score rank based on bucket [Source Data Type: varchar]"),
  `LOAN_CODE` INT64 OPTIONS(description = "Loan type [Source Data Type: varchar]"),
  `LOAN_TYP_ID` INT64 OPTIONS(description = "Loan subtype [Source Data Type: varchar]"),
  `LOAN_GRP` INT64 OPTIONS(description = "Loan group [Source Data Type: varchar]"),
  `AGENT_CODE1` INT64 OPTIONS(description = "Merchant group [Source Data Type: varchar]"),
  `AGENT_CODE2` INT64 OPTIONS(description = "Merchant subgroup [Source Data Type: varchar]"),
  `APPL_CHANNEL` STRING OPTIONS(description = "Application channel [Source Data Type: varchar]"),
  `REJECT_CODE` STRING OPTIONS(description = "Reject Code [Source Data Type: varchar]"),
  `FIN_AMT` FLOAT64 OPTIONS(description = "Easy payment finance approved amount [Source Data Type: numeric]"),
  `FIN_PRFT_AMT` FLOAT64 OPTIONS(description = "Easy payment profit/interest amount [Source Data Type: numeric]"),
  `FIN_TOTAL_AMT` FLOAT64 OPTIONS(description = "Easy payment financing total amount [Source Data Type: numeric]"),
  `INST_AMT` FLOAT64 OPTIONS(description = "Easy payment installment amount [Source Data Type: numeric]"),
  `DEPOSIT` INT64 OPTIONS(description = "% for downpayment [Source Data Type: numeric]"),
  `INTEREST` FLOAT64 OPTIONS(description = "Easy payment interest [Source Data Type: decimal]"),
  `TOTAL_INST` INT64 OPTIONS(description = "Easy payment total installment months; loan tenure [Source Data Type: numeric]"),
  `JointIncome_FG` STRING OPTIONS(description = "Joint income yes/no flag [Source Data Type: varchar]"),
  `SCORE_DECISION` STRING OPTIONS(description = "Easy payment score decision: accept/decline [Source Data Type: char]"),
  `NetIncome` FLOAT64 OPTIONS(description = "Easy payment applicant net income [Source Data Type: numeric]"),
  `Income` FLOAT64 OPTIONS(description = "Easy payment applicant income [Source Data Type: numeric]"),
  `Age` INT64 OPTIONS(description = "Easy payment applicant age [Source Data Type: int]"),
  `HomeYear` INT64 OPTIONS(description = "Number of years living in current residence [Source Data Type: numeric]"),
  `YearOfBusiness` INT64 OPTIONS(description = "Number of years of employment in current company [Source Data Type: numeric]"),
  `AnnualIncome` FLOAT64 OPTIONS(description = "Annual income [Source Data Type: numeric]"),
  `TOTAL_AEON_INST` INT64 OPTIONS(description = "Total installment for all Aeon products [Source Data Type: numeric]"),
  `TOTAL_AEON_OSB` FLOAT64 OPTIONS(description = "Total outstanding balance for all Aeon products [Source Data Type: numeric]"),
  `CUR_REPAY_RATIO` FLOAT64 OPTIONS(description = "Current repayment ratio [Source Data Type: decimal]"),
  `NEW_REPAY_RATIO` FLOAT64 OPTIONS(description = "New repayment ratio [Source Data Type: decimal]"),
  `NDI` FLOAT64 OPTIONS(description = "Net disposable income [Source Data Type: numeric]"),
  `CUR_DSR` FLOAT64 OPTIONS(description = "Current debt to service ratio [Source Data Type: decimal]"),
  `NEW_DSR` FLOAT64 OPTIONS(description = "New debt to service ratio [Source Data Type: decimal]"),
  `B_OtherIncome` FLOAT64 OPTIONS(description = "Other income [Source Data Type: numeric]"),
  `B_NonBankCommitment` FLOAT64 OPTIONS(description = "Non-bank commitment [Source Data Type: numeric]"),
  `DEPENDANT` INT64 OPTIONS(description = "Children, spouse. [Source Data Type: numeric]"),
  `YEAR_MADE` INT64 OPTIONS(description = "Easy payment vehicle year made [Source Data Type: varchar]"),
  `NOB` STRING OPTIONS(description = "Nature of Business [Source Data Type: varchar]"),
  `HomeOwner_flag` BOOL OPTIONS(description = "Ownership check of home [Source Data Type: varchar]"),
  `CIFState` STRING OPTIONS(description = "Customer address state as at application [Source Data Type: varchar]"),
  `Race` STRING OPTIONS(description = "Customer race as at application [Source Data Type: varchar]"),
  `Gender` STRING OPTIONS(description = "Customer gender as at application [Source Data Type: varchar]"),
  `Marital` STRING OPTIONS(description = "Customer marital status as at application [Source Data Type: varchar]"),
  `National` STRING OPTIONS(description = "Customer nationality as at application [Source Data Type: varchar]"),
  `Occupation` STRING OPTIONS(description = "Customer occupation as at application [Source Data Type: varchar]"),
  `Academic` STRING OPTIONS(description = "Customer academic qualification as at application [Source Data Type: varchar]"),
  `B_AdvInstallPymt` FLOAT64 OPTIONS(description = "Easy payment advanced install payment [Source Data Type: numeric]"),
  `AdvInstallPymtBand` STRING OPTIONS(description = "Easy payment advanced installment payment band [Source Data Type: nvarchar]"),
  `JudgeWeek_FG` INT64 OPTIONS(description = "Judge week flag [Source Data Type: varchar]"),
  `Biometric_FG` BOOL OPTIONS(description = "Biometric indicator [Source Data Type: varchar]"),
  `E-KYC` STRING OPTIONS(description = "E-KYC pass/fail [Source Data Type: varchar]"),
  `OTP` STRING OPTIONS(description = "OTP pass/fail [Source Data Type: varchar]"),
  `APPLY_FIN_AMT` FLOAT64 OPTIONS(description = "Easy payment applied financing amount [Source Data Type: numeric]"),
  `PreAssessment_Flag` BOOL OPTIONS(description = "Some customers qualify for pre-assessment [Source Data Type: varchar]")
) OPTIONS(description = "The current (daily full refreshed) application status (Approved or Rejected) for EP products. (Governed via Mock Metadata.xlsx | Sheet: T1 - Fact_EP_Judge)");

CREATE OR REPLACE TABLE `acsm_bronze.Fact_EP_Sales` (
  `TX_DT` FLOAT64 OPTIONS(description = "Sales Date"),
  `CIF_No` STRING OPTIONS(description = "Unique customer ID"),
  `TransactionCountry` STRING OPTIONS(description = "Ringgit Malaysia"),
  `TransactionCountryHigherLevel` STRING OPTIONS(description = "Local or Oversea"),
  `PriviledgeMerchantsGrp` STRING OPTIONS(description = "Member merchant"),
  `LDESC` STRING OPTIONS(description = "Spend Location"),
  `Sales_Type` STRING OPTIONS(description = "Cash Purchase or Cash Advance"),
  `Amount` FLOAT64 OPTIONS(description = "Transaction Amount"),
  `TransCount` FLOAT64 OPTIONS(description = "Transaction Count")
) OPTIONS(description = "The confirmed sales log of the EP product. (Governed via Mock Metadata.xlsx | Sheet: T2 - Fact_EP_Sales)");

CREATE OR REPLACE TABLE `acsm_bronze.Fact_EP_Collection` (
  `TX_DT` INT64 OPTIONS(description = "Reporting date [Source Data Type: decimal]"),
  `First_INST_DT` INT64 OPTIONS(description = "First intallment date [Source Data Type: decimal]"),
  `Agree_No` INT64 OPTIONS(description = "Loan agreement ID [Source Data Type: varchar]"),
  `CIF_No` INT64 OPTIONS(description = "Unique customer ID [Source Data Type: varchar]"),
  `Current_Time_Payment` INT64 OPTIONS(description = "current installment period [Source Data Type: varchar]"),
  `Del_Sts` INT64 OPTIONS(description = "Lock Deliquency status [Source Data Type: varchar]"),
  `Collection_Branch` INT64 OPTIONS(description = "Branch ID [Source Data Type: varchar]"),
  `Score_Value` INT64 OPTIONS(description = "Collection Score Point [Source Data Type: decimal]"),
  `Score_Grade` STRING OPTIONS(description = "Collection Score Grade [Source Data Type: varchar]"),
  `Sub_Code` STRING OPTIONS(description = "AKPK checker [Source Data Type: varchar]"),
  `Pay_in_Full` INT64 OPTIONS(description = "Account Status [Source Data Type: varchar]"),
  `Classification_Code` STRING OPTIONS(description = "Life Deliquency status [Source Data Type: varchar]"),
  `FinPlus_Code` STRING OPTIONS(description = "FinPlus (e-credit evaluation) tier [Source Data Type: varchar]"),
  `MDD` INT64 OPTIONS(description = "EP Multi Due Date [Source Data Type: varchar]"),
  `LoanTyp_ID` INT64 OPTIONS(description = "Loan product type indicator [Source Data Type: varchar]"),
  `Billing_OSP` FLOAT64 OPTIONS(description = "Principal Billing amount [Source Data Type: decimal]"),
  `Billing_Count` INT64 OPTIONS(description = "Principal Billing count [Source Data Type: decimal]"),
  `Collection_OSP` FLOAT64 OPTIONS(description = "Principal Collection amount [Source Data Type: decimal]"),
  `Collection_Count` INT64 OPTIONS(description = "Principal Collection count [Source Data Type: decimal]"),
  `Unpaid_OSP` FLOAT64 OPTIONS(description = "Principal Unpaid amount [Source Data Type: decimal]"),
  `Unpaid_Count` INT64 OPTIONS(description = "Principal Unpaid count [Source Data Type: decimal]")
) OPTIONS(description = "The collection status snapshot for EP products as at closing period (Governed via Mock Metadata.xlsx | Sheet: T3 - Fact_EP_Collection)");

CREATE OR REPLACE TABLE `acsm_bronze.Fact_CC_Judge` (
  `Rcd_DT` DATE OPTIONS(description = "Data extraction date [Source Data Type: date]"),
  `Account_No` INT64 OPTIONS(description = "Card account number [Source Data Type: varchar]"),
  `Appl_ID` INT64 OPTIONS(description = "Credit card application ID [Source Data Type: varchar]"),
  `ApplSts_ID` STRING OPTIONS(description = "Credit card application status ID [Source Data Type: varchar]"),
  `CIF_ID` INT64 OPTIONS(description = "Credit card customer ID [Source Data Type: varchar]"),
  `CardTyp_ID` STRING OPTIONS(description = "Credit card type [Source Data Type: varchar]"),
  `CardBrand_ID` STRING OPTIONS(description = "Credit card brand [Source Data Type: varchar]"),
  `CardApplTyp_ID` STRING OPTIONS(description = "Principal/supplementary [Source Data Type: varchar]"),
  `ApplChnnl_ID` STRING OPTIONS(description = "Credit card application channel [Source Data Type: varchar]"),
  `Reject_ID` INT64 OPTIONS(description = "Credit card rejection reason ID [Source Data Type: varchar]"),
  `Decline_ID` INT64 OPTIONS(description = "Rejection reason [Source Data Type: varchar]"),
  `Agent_ID` INT64 OPTIONS(description = "Merchant ID [Source Data Type: varchar]"),
  `ScoreDecision_ID` STRING OPTIONS(description = "Credit card score decision category [Source Data Type: varchar]"),
  `ScoreRank_ID` STRING OPTIONS(description = "Credit card score rank [Source Data Type: varchar]"),
  `SysRcmmd_ID` STRING OPTIONS(description = "System recommended decision [Source Data Type: varchar]"),
  `Gender` STRING OPTIONS(description = "Gender [Source Data Type: varchar]"),
  `Age` INT64 OPTIONS(description = "Age [Source Data Type: int]"),
  `Race` STRING OPTIONS(description = "Race [Source Data Type: varchar]"),
  `Nationality` STRING OPTIONS(description = "Nationality short code [Source Data Type: varchar]"),
  `MaritalSts` STRING OPTIONS(description = "Marital Status [Source Data Type: varchar]"),
  `Academic` STRING OPTIONS(description = "Highest academic qualification [Source Data Type: varchar]"),
  `YrStay` INT64 OPTIONS(description = "Number of years living in current residence [Source Data Type: int]"),
  `HomeOwn` STRING OPTIONS(description = "Type of home ownership [Source Data Type: varchar]"),
  `Occupation` STRING OPTIONS(description = "Occupation [Source Data Type: varchar]"),
  `NOB` STRING OPTIONS(description = "Nature of business of customers employer [Source Data Type: varchar]"),
  `YrJob` INT64 OPTIONS(description = "Year in job [Source Data Type: int]"),
  `NetIncome` INT64 OPTIONS(description = "Net income [Source Data Type: int]"),
  `GrossIncome` INT64 OPTIONS(description = "Gross income [Source Data Type: int]"),
  `AnnualIncome` INT64 OPTIONS(description = "Annual income [Source Data Type: int]"),
  `AnnualIncomeTotLmt` INT64 OPTIONS(description = "Annual income total limit [Source Data Type: int]"),
  `CurrRepay` INT64 OPTIONS(description = "Current repayment amount [Source Data Type: int]"),
  `NewRepay` INT64 OPTIONS(description = "New repayment amount [Source Data Type: int]"),
  `RcmmdIntrst` FLOAT64 OPTIONS(description = "Recommended interest rate [Source Data Type: decimal]"),
  `NDI` INT64 OPTIONS(description = "Net Disposable Income [Source Data Type: int]"),
  `CurrDSR` INT64 OPTIONS(description = "Current DSR [Source Data Type: decimal]"),
  `NewDSR` INT64 OPTIONS(description = "New DSR [Source Data Type: decimal]"),
  `PaySlipTyp_ID` INT64 OPTIONS(description = "Payslip type [Source Data Type: varchar]"),
  `CardActivate_FG` BOOL OPTIONS(description = "Card activated [Source Data Type: varchar]"),
  `EmergencyCont_FG` BOOL OPTIONS(description = "Emergency contact provided [Source Data Type: varchar]"),
  `CardActivate_DT` INT64 OPTIONS(description = "Card activation date [Source Data Type: decimal]"),
  `Judge_DT` INT64 OPTIONS(description = "Decision date [Source Data Type: decimal]"),
  `Appl_DT` INT64 OPTIONS(description = "Application date [Source Data Type: decimal]"),
  `B_Limit` FLOAT64 OPTIONS(description = "Total limit [Source Data Type: decimal]"),
  `B_CrLimit` INT64 OPTIONS(description = "Credit limit [Source Data Type: decimal]"),
  `B_CashAdvLimit` FLOAT64 OPTIONS(description = "Cash advance limit [Source Data Type: decimal]"),
  `B_NonBankCommitment` FLOAT64 OPTIONS(description = "Non bank commitment [Source Data Type: decimal]"),
  `CIFState_ID` STRING OPTIONS(description = "State [Source Data Type: varchar]"),
  `Biometric_FG` STRING OPTIONS(description = "Biometric indicator [Source Data Type: varchar]"),
  `FinalDecline_ID` INT64 OPTIONS(description = "Decline ID [Source Data Type: varchar]"),
  `Final_Score` INT64 OPTIONS(description = "Credit card CTOS score [Source Data Type: decimal]"),
  `Final_Score_Type` INT64 OPTIONS(description = "Credit card CTOS score [Source Data Type: decimal]"),
  `Final_ScoreDesc` STRING OPTIONS(description = "Credit card CTOS score description [Source Data Type: varchar]"),
  `ApplyCardBiz_ID` STRING OPTIONS(description = "Applied card ID [Source Data Type: varchar]"),
  `ProposedCardBiz_ID` STRING OPTIONS(description = "Proposed card ID [Source Data Type: varchar]")
) OPTIONS(description = "The current (daily full refreshed) application status (Approved or Rejected) for credit cards. (Governed via Mock Metadata.xlsx | Sheet: T4 - Fact_CC_Judge)");

CREATE OR REPLACE TABLE `acsm_bronze.Fact_CC_Sales` (
  `TX_DT` INT64 OPTIONS(description = "Sales Date [Source Data Type: decimal]"),
  `CIF_No` INT64 OPTIONS(description = "Unique customer ID [Source Data Type: varchar]"),
  `TransactionCountry` STRING OPTIONS(description = "Ringgit Malaysia [Source Data Type: varchar]"),
  `TransactionCountryHigherLevel` STRING OPTIONS(description = "Local or Oversea [Source Data Type: varchar]"),
  `PriviledgeMerchantsGrp` STRING OPTIONS(description = "Member merchant [Source Data Type: varchar]"),
  `LDESC` STRING OPTIONS(description = "Spend Location [Source Data Type: varchar]"),
  `Sales_Type` STRING OPTIONS(description = "Cash Purchase or Cash Advance [Source Data Type: varchar]"),
  `Amount` FLOAT64 OPTIONS(description = "Transaction Amount [Source Data Type: decimal]"),
  `TransCount` INT64 OPTIONS(description = "Transaction Count [Source Data Type: decimal]")
) OPTIONS(description = "The actual spending & cash advance log on credit card (Governed via Mock Metadata.xlsx | Sheet: T5 - Fact_CC_Sales)");

CREATE OR REPLACE TABLE `acsm_bronze.Fact_CC_Collection` (
  `TX_DT` INT64 OPTIONS(description = "Reporting date [Source Data Type: decimal]"),
  `Account_No` INT64 OPTIONS(description = "CC account ID [Source Data Type: varchar]"),
  `CIF_No` INT64 OPTIONS(description = "Unique customer ID [Source Data Type: varchar]"),
  `DC_Sts` INT64 OPTIONS(description = "Lock deliquency status [Source Data Type: varchar]"),
  `Application_Branch` INT64 OPTIONS(description = "Branch ID [Source Data Type: varchar]"),
  `Score_Value` INT64 OPTIONS(description = "Collection Score point [Source Data Type: decimal]"),
  `Score_Grade` STRING OPTIONS(description = "Collection Score grade [Source Data Type: varchar]"),
  `MDD` INT64 OPTIONS(description = "CC Due Date [Source Data Type: varchar]"),
  `FinPlus_Code` STRING OPTIONS(description = "FinPlus (e-credit evaluation) tier [Source Data Type: varchar]"),
  `Billing_OSP` FLOAT64 OPTIONS(description = "Billing amount [Source Data Type: decimal]"),
  `Billing_Count` INT64 OPTIONS(description = "Billing count [Source Data Type: decimal]"),
  `Collection_OSP` FLOAT64 OPTIONS(description = "Collection amount [Source Data Type: decimal]"),
  `Collection_Count` INT64 OPTIONS(description = "Collection count [Source Data Type: decimal]"),
  `Unpaid_OSP` FLOAT64 OPTIONS(description = "Unpaid amount [Source Data Type: decimal]"),
  `Unpaid_Count` INT64 OPTIONS(description = "Unpaid count [Source Data Type: decimal]"),
  `Maintain_OSP` FLOAT64 OPTIONS(description = "Maintain amount [Source Data Type: decimal]"),
  `Maintain_Count` INT64 OPTIONS(description = "Maintain count [Source Data Type: decimal]")
) OPTIONS(description = "The billing and collection status snapshot for credit cards as at closing period (Governed via Mock Metadata.xlsx | Sheet: T6 - Fact_CC_Collection)");

CREATE OR REPLACE TABLE `acsm_bronze.m3CIF` (
  `Rcd_DT` DATE OPTIONS(description = "Record refresh date [Source Data Type: date]"),
  `CIF_ID` INT64 OPTIONS(description = "Customer ID [Source Data Type: varchar]"),
  `CIF_NM` STRING OPTIONS(description = "Customer name [Source Data Type: varchar]"),
  `CIF_NM1` STRING OPTIONS(description = "Customer name [Source Data Type: varchar]"),
  `CIF_NM2` STRING OPTIONS(description = "Customer name [Source Data Type: varchar]"),
  `MaritalSts` STRING OPTIONS(description = "MaritalStatus [Source Data Type: varchar]"),
  `Gender` STRING OPTIONS(description = "Gender [Source Data Type: varchar]"),
  `Citizen` STRING OPTIONS(description = "Citizen [Source Data Type: varchar]"),
  `State` STRING OPTIONS(description = "State [Source Data Type: varchar]"),
  `Region` STRING OPTIONS(description = "Region [Source Data Type: varchar]"),
  `Race` STRING OPTIONS(description = "Race [Source Data Type: varchar]"),
  `NOB` STRING OPTIONS(description = "Nature of business [Source Data Type: varchar]"),
  `HomeOwn` STRING OPTIONS(description = "Customer homeowner category [Source Data Type: varchar]"),
  `HomePost` INT64 OPTIONS(description = "Customer home postcode [Source Data Type: varchar]"),
  `_HomeAddr1` STRING OPTIONS(description = "_HomeAddr1 [Source Data Type: varchar]"),
  `_HomeAddr2` STRING OPTIONS(description = "_HomeAddr2 [Source Data Type: varchar]"),
  `_HomeAddr3` STRING OPTIONS(description = "_HomeAddr3 [Source Data Type: varchar]"),
  `EmpPost` INT64 OPTIONS(description = "Employment Postal Code [Source Data Type: varchar]"),
  `MailPost` INT64 OPTIONS(description = "Mail Postal Code [Source Data Type: varchar]"),
  `Occupation` STRING OPTIONS(description = "Occupation [Source Data Type: varchar]"),
  `PayslipTyp` INT64 OPTIONS(description = "PayslipTyp [Source Data Type: varchar]"),
  `Academic` STRING OPTIONS(description = "Academic qualifications [Source Data Type: varchar]"),
  `Emp_NM` STRING OPTIONS(description = "Employer Name [Source Data Type: varchar]"),
  `SelftEmp_FG` STRING OPTIONS(description = "Self Employment Indicator [Source Data Type: varchar]"),
  `Felda_FG` STRING OPTIONS(description = "Felda is a government program to help rural Malaysians. [Source Data Type: varchar]"),
  `JoinIncome_FG` STRING OPTIONS(description = "Joint Income Indicator [Source Data Type: varchar]"),
  `RecvPromo_FG` STRING OPTIONS(description = "Received promotion indicator [Source Data Type: varchar]"),
  `N_Age` INT64 OPTIONS(description = "Age [Source Data Type: numeric]"),
  `N_YrStay` INT64 OPTIONS(description = "Number of years living in current residence [Source Data Type: numeric]"),
  `N_YrJob` INT64 OPTIONS(description = "Number of years in current job [Source Data Type: numeric]"),
  `B_NetIncome` FLOAT64 OPTIONS(description = "Net Income [Source Data Type: numeric]"),
  `B_GrossIncome` FLOAT64 OPTIONS(description = "Gross Income [Source Data Type: numeric]"),
  `B_AnnualIncome` FLOAT64 OPTIONS(description = "Annual Income [Source Data Type: numeric]"),
  `EmpSts` INT64 OPTIONS(description = "Employment Status [Source Data Type: int]")
) OPTIONS(description = "Customer latest status daily refresh table (Governed via Mock Metadata.xlsx | Sheet: T7 - m3CIF)");

CREATE OR REPLACE TABLE `acsm_bronze.dimProduct` (
  `Expiry_DT` INT64 OPTIONS(description = "Card expiry date [Source Data Type: varchar]"),
  `FirstSpend_DT` INT64 OPTIONS(description = "First spend date [Source Data Type: varchar]"),
  `Block_Code` STRING OPTIONS(description = "If card is blocked [Source Data Type: varchar]"),
  `Block_Date` INT64 OPTIONS(description = "If card is blocked [Source Data Type: numeric]"),
  `CIC_Status` STRING OPTIONS(description = "CIC status [Source Data Type: varchar]"),
  `Card_Status` STRING OPTIONS(description = "Card status [Source Data Type: varchar]"),
  `AKPK_Status` STRING OPTIONS(description = "AKPK status [Source Data Type: varchar]"),
  `Card_First_Emboss_Date` INT64 OPTIONS(description = "Physical card issuance date [Source Data Type: numeric]"),
  `Card_Emboss_Date` INT64 OPTIONS(description = "Card emboss date [Source Data Type: numeric]"),
  `Card_First_Activated_Date` INT64 OPTIONS(description = "Card first activated date [Source Data Type: numeric]"),
  `Card_Activated_Date` INT64 OPTIONS(description = "Card current activated date [Source Data Type: numeric]"),
  `CP_CL` FLOAT64 OPTIONS(description = "Credit Purchase Total Limit [Source Data Type: numeric]"),
  `CP_CL_Available` FLOAT64 OPTIONS(description = "Credit Purchase Available Limit [Source Data Type: numeric]"),
  `CA_CL` FLOAT64 OPTIONS(description = "Credit Advance Total Limit [Source Data Type: numeric]"),
  `CA_CL_Available` FLOAT64 OPTIONS(description = "Credit Advance Available Limit [Source Data Type: numeric]"),
  `CP_CL_Usage` FLOAT64 OPTIONS(description = "Credit Purchase Usage [Source Data Type: numeric]"),
  `CA_CL_Usage` FLOAT64 OPTIONS(description = "Credit Advance Usage [Source Data Type: numeric]"),
  `CIF_ID` INT64 OPTIONS(description = "Unique customer ID [Source Data Type: varchar]"),
  `Account_No` INT64 OPTIONS(description = "Card account number [Source Data Type: numeric]"),
  `Account_Agree_Sts` STRING OPTIONS(description = "Account agreement status [Source Data Type: varchar]"),
  `Virtual_Card_Flag` STRING OPTIONS(description = "Virtual card indicator [Source Data Type: varchar]"),
  `Wallet_Tier` STRING OPTIONS(description = "Loyalty account Tier [Source Data Type: varchar]")
) OPTIONS(description = "The current and daily full refresh master record of all active cards (Governed via Mock Metadata.xlsx | Sheet: T8 - dimProduct)");

