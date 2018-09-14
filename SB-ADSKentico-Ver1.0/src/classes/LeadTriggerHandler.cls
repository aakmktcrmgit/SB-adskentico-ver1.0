/*
Author : Nikhil Agarwal/ Ashish Pandey
Date : 05/05/2017
Description : This is a global class to handle all Lead triggers.... check in commit//13/09:1:04  ....!!11--testing push GIt
*/

global class LeadTriggerHandler extends ADS_TriggerHandler{
    protected override void beforeInsert()
    {
        encryptDataonInsert(Trigger.New);
        riskCalculation_MIFID(trigger.new);
        IBNameToIBCode('insert');
        checkDuplicates('insert');
    }
    protected override void afterInsert()
    {
        afterInsertMethod();
        recordEncryption_onInsert();
    }
    protected override void beforeUpdate()
    {
        encryptDataonUpdate();
        riskCalculation_MIFID(trigger.new);
        IBNameToIBCode('update');
        checkDuplicates('update');
        createHistoryTracking();
        
    }    
    protected override void afterUpdate()
    {
        afterUpdateMethod(Trigger.New);
        afterInsertMethod();        
    }
    
    ///////////////////////////////////////////////////////////////////////
    /*   Author : Nikhil Agarwal
         Description : Below code will encrypt data on lead insertion. The code is dynamic and fields are defined in custom label*/
         
    public void encryptDataonInsert(List<Lead> lstLeadstobeEncrypted){
        Blob cryptoKey = EncodingUtil.base64Decode(System.Label.X256_Encryption_Key);
        Map<id,Lead> oldMap = (Map<id,Lead>)Trigger.oldMap;     
        Map<id,Lead> newMap = (Map<id,Lead>)Trigger.newMap;
        Map<string,id> MapReferralCodeandOwnerId = new Map<string,id>();
        Map<Id,String> MapRTID_Name = new Map<Id,String>();        
        Set<String> setReferralID = new set<String>();        
        
        for(RecordType RT : [Select id, DeveloperName, name, SobjectType from RecordType where SobjectType = 'Lead'])
        {
            MapRTID_Name.put(RT.id, RT.DeveloperName);
        }           
        for(Lead objLead:lstLeadstobeEncrypted){            
            // WF-33 Copy Email into Email 2
            if(objLead.Email != null && objLead.Email !=''){
                objLead.Email_2__c = objLead.Email;
            }
            //backend field to update the Contact's "Primary Contact" field on Lead conversion(Mapping defined on Lead Conversion)
            objLead.Primary_Contact__c = true;            
            for(String strField:System.Label.LeadsFieldsToBeEncrypted.split(',')){
                strField = strField.trim();
                String strDupField;
                String strEncryptedField;
                if(strField.contains('__c')){
                    strDupField = strField.remove('__c') + '_dup__c';
                    strEncryptedField = strField.remove('__c') +'_Encrypted__c';
                }
                else{ 
                    strDupField = strField + '_dup__c';
                    strEncryptedField = strField +'_Encrypted__c';
                }
                               
                if(objLead.get(strDupField) != '' && objLead.get(strDupField) != null){
                    objLead.put(strField,objLead.get(strDupField));
                    objLead.put(strDupField,'');
                }
                if(objLead.get(strField) != '' && objLead.get(strField) != null){
                    String strfieldvalue = '' + objLead.get(strField);
                    Blob b1 = Blob.valueOf(strfieldvalue);
                    Blob blobEncryptedb1 = Crypto.encryptWithManagedIV('AES256', cryptoKey, b1);
                    objLead.put(strEncryptedField,EncodingUtil.base64Encode(blobEncryptedb1));
                }
            }
            
                        
            // WF-1-Everytime
            objLead.WFLeadId__c = objLead.id;
            if(MapRTID_Name.containsKey(objLead.recordTypeId))
            {
              objLead.WFLeadRT__c = MapRTID_Name.get(objLead.recordTypeId);
            }
            if(objLead.Action__c != null){
                objLead.Last_Status_Modified_Date__c = DateTime.Now();
            }
            if(objLead.Referred_By__c != null && objLead.Referred_By__c != ''){
                setReferralID.add(objLead.Referred_By__c);   
            }
            // WF-2,3,4,5 -Low,Medium,High Risk and Do Not Deal Countries
            if(objLead.Country_of_Residence__c != null && System.Label.COR_Low_Risk.contains(objLead.Country_of_Residence__c)){
                objLead.CountryRisk__c = 'Low Risk';
            }
            else if(objLead.Country_of_Residence__c != null && (System.Label.COR_Medium_Risk_1.contains(objLead.Country_of_Residence__c) || System.Label.COR_Medium_Risk_2.contains(objLead.Country_of_Residence__c) || System.Label.COR_Medium_Risk_3.contains(objLead.Country_of_Residence__c))){
                objLead.CountryRisk__c = 'Medium Risk';
            }
            else if(objLead.Country_of_Residence__c != null && System.Label.COR_High_Risk.contains(objLead.Country_of_Residence__c)){
                objLead.CountryRisk__c = 'High Risk';
            }
            else if(objLead.Country_of_Residence__c != null && System.Label.COR_Do_Not_Deal.contains(objLead.Country_of_Residence__c)){
                objLead.CountryRisk__c = 'Do Not Deal';
                objLead.Status = 'Unqualified';
                objLead.Unqualified__c = 'Restricted Region';
            }
            // WF-6-To copy postal code in po box address
            if(objLead.PostalCode != null){
            objLead.P_O_box_Address__c = objLead.PostalCode;
            }
            // WF-7-Set entity for London leads
            if(objLead.Entity__c == 'London Retail' && objLead.IB_ID__c == null){
                objLead.IB_ID__c = 'ADSLondon';
            } 
            // WF-8-AD CS Document Verification
            if(objLead.Account_Application__c != null && objLead.POI__c != null && objLead.POR__c != null)
            {
                objLead.Compliance_Status__c = 'Waiting Approval';
            }   
            // WF-9-Check Abu dhabi IB-ID   
            if(objLead.Entity__c == 'Abu Dhabi' && objLead.IB_ID__c == null)
            {
                objLead.IB_ID__c = 'ADADS';
            }
            //  WF-10-HK Entity
            if(objLead.Entity__c == 'Hong Kong')
            {
                objLead.ADSS_Region__c = 'ADADS';
                objLead.Company = objLead.Firstname + objLead.LastName;
            }
            // WF-11-IB ads00062 Rules -- Omar Qaryouti IB related leads
            if(objLead.IB_ID__c!= null && objLead.IB_ID__c.length()>=8)
            {
                if(objLead.IB_ID__c.contains('ads00062'))
                {
                    objLead.Prime__c = False;
                    objLead.Lead_Origin__c = 'IB';
                }
            }   
            // WF-12-Lead Created - Origin cmp Field Update
            if(objLead.cmp__c != null)
            {
                objLead.Origin_cmp__c = objLead.cmp__c;
            }
            // WF-13-Intersted_LeadStatus to ColdLeadRating
            if(objLead.Status == 'Existing Account' || objLead.Status == 'Unqualified')
            {
                objLead.Rating = 'Cold';
            }
            // WF-14-Intersted_LeadStatus to Hot_LeadRating 
            if(objLead.Status == 'Interested')
            {
                objLead.Rating = 'Hot';
            }
            // WF-15-Lead Created - Origin Entity Field Update 
            if(objLead.Entity__c != null)
            {
                objLead.Origin_Entity__c = objLead.Entity__c;
            }
            // WF-16-Lead Created - Origin IB-ID Field Update
            if(objLead.IB_ID__c != null)
            {
                objLead.Origin_IB_ID__c = objLead.IB_ID__c;
            }
            // WF-17-Lead Created - Origin Lead Origin Field Update 
            if(objLead.Lead_Origin__c != null)
            {
                objLead.Origin_Lead_Origin__c = objLead.Lead_Origin__c;
            }
            // WF-18-Lead Created - Origin Lead Source Field Update
            if(objLead.LeadSource != null)
            {
                objLead.Origin_Lead_Source__c = objLead.LeadSource;
            }
            // WF-19-Lead Created - Origin utm_campaign Field Update 
            if(objLead.utm_campaign__c != null)
            {
                objLead.Origin_utm_campaign__c = objLead.utm_campaign__c;
            }
            // WF-20-Lead Created - Origin utm_cmp Field Update 
            if(objLead.utm_cmp__c != null)
            {
                objLead.Origin_utm_cmp__c = objLead.utm_cmp__c;
            }
            // WF-21-Lead Created - Origin utm_medium Field Update 
            if(objLead.utm_medium__c != null)
            {
                objLead.Origin_utm_medium__c = objLead.utm_medium__c;
            }
            // WF-22-Lead Created - Origin utm_source Field Update 
            if(objLead.utm_source__c != null)
            {
                objLead.Origin_utm_source__c = objLead.utm_source__c;
            }
            //Updating Origin Source with Source
            if(objLead.source__c != null)
            {
                objLead.Origin_source__c = objLead.source__c;
            }
            
            // WF-23-Lead Created Date Captured 
            if(objLead.CreatedDate != null)
            {
                objLead.CreatedDateOriginal__c = objLead.CreatedDate;
            }
             
            // WF-24-Singapore Leads 
            if(objLead.Entity__c == 'Singapore-AD')
            {
                objLead.Account_Type__c = 'Prime Lite';
            }
            // WF-25-Update Created Date 
            if(objLead.Entity__c == 'Abu Dhabi' || objLead.Entity__c == 'Singapore-AD' || objLead.Entity__c == 'ADS-London' || objLead.Entity__c == 'Singapore' || objLead.Entity__c == 'Hong Kong' || objLead.Entity__c == 'Hong Kong Retail' || objLead.Entity__c == 'London Retail')
            {
                objLead.Converted_Day__c = objLead.CreatedDate;
            }
            // WF-26-Lead Status Change Date
            if(objLead.status != null)
            {
                objLead.Lead_Status_Change__c = Datetime.now();
            }
            // WF-27-Check Client portal Stage
            if(objLead.Client_Portal_Stage__c == 'Page2 Completed' && (objLead.Status != 'Approved' && objLead.Status != 'CS AD Rejected' && objLead.Status != 'Qualified' && objLead.Status != 'Unqualified') && objLead.isConverted == false && (objLead.Entity__c == 'Abu Dhabi' || objLead.Entity__c == 'ADS-London-AD'))
            {
                objLead.status = 'Pending CS Team Approval';
                objLead.Page_2_Completed_Date__c = datetime.now();
            }
            // WF-28-Check Singapore IB CP 
            if(objLead.Entity__c == 'Singapore-AD' && (objLead.LeadSource == 'Client-Portal-Lead-Cn' || objLead.LeadSource == 'Client-Portal-Live-Cn') && objLead.IB_ID__c!= null && objLead.IB_ID__c.contains('ads'))
            {
                objLead.Notify__c = true;
            } 
            
            // WF-29-Contacted_LeadStatus to Warm_LeadRating
            if(objLead.Status == 'Contacted 1' || objLead.Status == 'Contacted 2' || objLead.Status == 'Contacted 3')
            {
                objLead.Rating = 'Warm';
            }
            
            // WF-30-Risk Category Update
            if(objLead.Total_KYC_Risk_Score__c != null)
            {
                if(objLead.Total_KYC_Risk_Score__c <= 4.00)
                {
                    objLead.Risk_Category__c = 'Low';
                }
                else if(objLead.Total_KYC_Risk_Score__c > 4.00 && objLead.Total_KYC_Risk_Score__c <= 8.00)
                {
                    objLead.Risk_Category__c = 'Medium';
                }
                else if(objLead.Total_KYC_Risk_Score__c > 8.00 && objLead.Total_KYC_Risk_Score__c <= 12.00)
                {
                    objLead.Risk_Category__c = 'High';
                }else
                {
                    ObjLead.Risk_Category__c = 'Fail';
                }
            }
            /* // WF-31-Update Time Stamp Sent for Approval
            if(objLead.Status == 'Pending CS Team Approval' )
            {
                objLead.Time_duration_Create_Lead_Sent_For_App__c = System.now() - objLead.CreatedDate;
            } */
            
            // WF-32-Lead Next Action Copy-LDN
            if(objLead.Action__c == 'Call 1' || objLead.Action__c == 'Call 2' || objLead.Action__c == 'Call 3' || objLead.Action__c == 'Call 4' || objLead.Action__c == 'Call 5' || objLead.Action__c == 'Call 6' || objLead.Action__c == 'Call 7')
            {
                objLead.Next_Action_copy__c = objLead.Next_Action__c;
            }
            // Below code will check flag for Lead to be created in IB Portal
            /* if(objLead.Entity__c != null && objLead.Entity__c != '' && objLead.RecordTypeId != System.Label.Wealth_Mgt_RT_Lead && objLead.Is_Test__c == false){
                objLead.IB_Portal_Insert__c = true;             
            } */
        }
        for(Account objAcc:[select id,OwnerID,Owner.IsActive,Referral_Code_ID__c from Account where Referral_Code_ID__c IN:setReferralID and Owner.IsActive = true]){
            MapReferralCodeandOwnerId.put(objAcc.Referral_Code_ID__c,objAcc.OwnerID);
        }
        
        for(Lead objLead : (List<Lead>)Trigger.new){
            if(MapReferralCodeandOwnerId.get(objLead.Referred_By__c) != null)
                objLead.Referral_Owner__c = MapReferralCodeandOwnerId.get(objLead.Referred_By__c);
            }
        
    
        
    } 
    
     /*   Author : Nikhil Agarwal
          Description : Below code will encrypt data on lead update. The code is dynamic and fields are defined in custom label*/
          
    public void encryptDataonUpdate(){
        Blob cryptoKey = EncodingUtil.base64Decode(System.Label.X256_Encryption_Key);
        Map<id,Lead> oldMap = (Map<id,Lead>)Trigger.oldMap;
        Map<id,Lead> newMap = (Map<id,Lead>)Trigger.newMap;
        Map<Id,String> MapRTID_Name = new Map<Id,String>();
        Map<Id,String> mapUserIDtoName = new Map<Id,String>();
        List<History_Tracking__c> lstHT = new list<History_Tracking__c>();
        List<CampaignMember> lstCampaignMember = new List<CampaignMember>();
        Map<string,id> mapUTMCampaignandID = new map<string,id>();              
        Set<String> setReferralID = new set<String>();      
        Map<string,id> MapReferralCodeandOwnerId = new Map<string,id>();
        for(Campaign camp :[select id,utmcampaign__c,utmsource__c,RecordTypeId,IsActive,Auto_Campaign_Member_Creation__c from Campaign where (RecordTypeId =: System.Label.Monthly_Campaign or RecordTypeId =: System.Label.Seminars or RecordTypeId =: System.Label.UTM_Source) and (utmcampaign__c != null or utmsource__c != null) and IsActive = true and Auto_Campaign_Member_Creation__c = true]){
            if(camp.utmcampaign__c != null)
                mapUTMCampaignandID.put(camp.utmcampaign__c,camp.id);
            else if(camp.utmsource__c != null)
                mapUTMCampaignandID.put(camp.utmsource__c,camp.id);
        }
        for(User us : [Select id, name from User where isActive = true])
        {
            mapUserIDtoName.put(us.id,us.name);
        }
        for(RecordType RT : [Select id, DeveloperName, name, SobjectType from RecordType where SobjectType = 'Lead'])
        {
            MapRTID_Name.put(RT.id, RT.DeveloperName);
        } 
        Id id1 = UserInfo.getProfileId();
        String profileName = [Select Id,Name from Profile where Id=:id1].Name;    
        
        for(Lead objLead:newMap.values()){
            for(String strField:System.Label.LeadsFieldsToBeEncrypted.split(',')){
                strField = strField.trim();
                String strDupField;
                String strEncryptedField;
                if(strField.contains('__c')){
                    strDupField = strField.remove('__c') + '_dup__c';
                    strEncryptedField = strField.remove('__c') +'_Encrypted__c';
                }
                else{ 
                    strDupField = strField + '_dup__c';
                    strEncryptedField = strField +'_Encrypted__c';
                }
                
                String strdupfieldvalue = ''+objLead.get(strDupField);
                if(objLead.get(strDupField) != objLead.get(strField) && objLead.get(strDupField) != null && objLead.get(strDupField) != '' && !strdupfieldvalue.contains('blank')){                 
                    History_Tracking__c objHT = new History_Tracking__c();
                    if(objLead.get(strField) != null && objLead.get(strField) != '')
                        objHT.Prior_Value__c = ''+objLead.get(strField);
                    else
                        objHT.Prior_Value__c = '';
                    objHT.Current_Value__c = ''+objLead.get(strDupField);
                    objHT.Changed_By__c = UserInfo.getUserID();
                    objHT.Changed_Date_Time__c = DateTime.Now();
                    objHT.Lead__c = objLead.id;
                    objHT.Field_Name__c = strField;
                    objHT.Tech_Email_Phone_field__c = true;
                    lstHT.add(objHT);
                    objLead.put(strField,objLead.get(strDupField));
                    objLead.put(strDupField,'');                
                }
                else if(objLead.get(strDupField) != objLead.get(strField) && strdupfieldvalue.contains('blank')){
                    History_Tracking__c objHT = new History_Tracking__c();
                    objHT.Prior_Value__c = ''+objLead.get(strField);
                    objHT.Current_Value__c = '';
                    objHT.Changed_By__c = UserInfo.getUserID();
                    objHT.Changed_Date_Time__c = DateTime.Now();
                    objHT.Lead__c = objLead.id;
                    objHT.Field_Name__c = strField;
                    objHT.Tech_Email_Phone_field__c = true;
                    lstHT.add(objHT);
                    objLead.put(strField,'');
                    objLead.put(strDupField,'');                
                }
                
                if(objLead.get(strField) == '' || objLead.get(strField) == null)
                    objLead.put(strEncryptedField,'');
                
                else if(oldMap.get(objLead.id).get(strField) != objLead.get(strField) && objLead.get(strField) != '' && objLead.get(strField) != null){
                    String strfieldvalue = '' + objLead.get(strField);
                    Blob b1 = Blob.valueOf(strfieldvalue);
                    Blob blobEncryptedb1 = Crypto.encryptWithManagedIV('AES256', cryptoKey, b1);
                    objLead.put(strEncryptedField,EncodingUtil.base64Encode(blobEncryptedb1));
                }               
            }
            if(objLead.Referred_By__c != oldMap.get(objLead.id).Referred_By__c && objLead.Referred_By__c != null && objLead.Referred_By__c != ''){
                setReferralID.add(objLead.Referred_By__c);   
            }            
            if(objLead.utm_campaign__c != '' && objLead.utm_campaign__c != null && objLead.utm_campaign__c != oldMap.get(objLead.id).utm_campaign__c){
                if(mapUTMCampaignandID.get(objLead.utm_campaign__c) != null){
                    CampaignMember objCamMember = new CampaignMember();
                    objCamMember.CampaignID = mapUTMCampaignandID.get(objLead.utm_campaign__c);
                    objCamMember.LeadId  = objLead.Id;
                    objCamMember.MemberAddedby__c = 'Automated Entry';
                    lstCampaignMember.add(objCamMember);
                }
            }            
            if(objLead.utm_source__c != '' && objLead.utm_source__c != null && objLead.utm_source__c != oldMap.get(objLead.id).utm_source__c){
                if(mapUTMCampaignandID.get(objLead.utm_source__c) != null){
                    CampaignMember objCamMember = new CampaignMember();
                    objCamMember.CampaignID = mapUTMCampaignandID.get(objLead.utm_source__c);
                    objCamMember.LeadId  = objLead.Id;
                    objCamMember.MemberAddedby__c = 'Automated Entry';
                    lstCampaignMember.add(objCamMember);
                }
            }            
            objLead.WFLeadId__c = objLead.id;
            if(MapRTID_Name.containsKey(objLead.recordTypeId))
            {
              objLead.WFLeadRT__c = MapRTID_Name.get(objLead.recordTypeId);
            }
            if(objLead.Action__c != null && oldMap.get(objLead.id).Action__c != objLead.Action__c){
                objLead.Last_Status_Modified_Date__c = DateTime.Now();
            }
            if(objLead.Country_of_Residence__c != null && System.Label.COR_Low_Risk.contains(objLead.Country_of_Residence__c)){
                objLead.CountryRisk__c = 'Low Risk';
            }
            else if(objLead.Country_of_Residence__c != null && (System.Label.COR_Medium_Risk_1.contains(objLead.Country_of_Residence__c) || System.Label.COR_Medium_Risk_2.contains(objLead.Country_of_Residence__c) || System.Label.COR_Medium_Risk_3.contains(objLead.Country_of_Residence__c))){
                objLead.CountryRisk__c = 'Medium Risk';
            }
            else if(objLead.Country_of_Residence__c != null && System.Label.COR_High_Risk.contains(objLead.Country_of_Residence__c)){
                objLead.CountryRisk__c = 'High Risk';
            }
            else if(objLead.Country_of_Residence__c != null && System.Label.COR_Do_Not_Deal.contains(objLead.Country_of_Residence__c)){
                objLead.CountryRisk__c = 'Do Not Deal';
                objLead.Status = 'Unqualified';
                objLead.Unqualified__c = 'Restricted Region ';
            }
            if(objLead.PostalCode != null){
            objLead.P_O_box_Address__c = objLead.PostalCode;
            }
            if((oldMap.get(objLead.id).Entity__c != objLead.Entity__c || oldMap.get(objLead.id).IB_ID__c != objLead.IB_ID__c) && (objLead.Entity__c == 'London Retail' && objLead.IB_ID__c == null)){
                objLead.IB_ID__c = 'ADSLondon';
            }
            // AD CS Document Verification
            if((oldMap.get(objLead.id).Account_Application__c != objLead.Account_Application__c || oldMap.get(objLead.id).POI__c != objLead.POI__c || oldMap.get(objLead.id).POR__c != objLead.POR__c) && (objLead.Account_Application__c != null && objLead.POI__c != null && objLead.POR__c != null))
            {
                objLead.Compliance_Status__c = 'Waiting Approval';
            }   
            // Intersted_LeadStatus to ColdLeadRating
            if(oldMap.get(objLead.id).Status != objLead.Status && (objLead.Status == 'Existing Account' || objLead.Status == 'Unqualified'))
            {
                objLead.Rating = 'Cold';
            }
            // Intersted_LeadStatus to Hot_LeadRating   
            if(oldMap.get(objLead.id).Status != objLead.Status && objLead.Status == 'Interested')
            {
                objLead.Rating = 'Hot';
            }
            // WF-26-Lead Status Change Date
            if(objLead.status != null && oldMap.get(objLead.id).status != objLead.status){
                objLead.Lead_Status_Change__c = DateTime.Now();
            }
            // WF-27-Check Client portal Stage
            if((oldMap.get(objLead.id).Client_Portal_Stage__c != objLead.Client_Portal_Stage__c || oldMap.get(objLead.id).Status != objLead.Status || oldMap.get(objLead.id).Entity__c != objLead.Entity__c) && (objLead.Client_Portal_Stage__c == 'Page2 Completed' && (objLead.Status != 'Approved' && objLead.Status != 'CS AD Rejected' && objLead.Status != 'Qualified' && objLead.Status != 'Unqualified') && objLead.isConverted == false && (objLead.Entity__c == 'Abu Dhabi' || objLead.Entity__c == 'ADS-London-AD')))
            {
                objLead.status = 'Pending CS Team Approval';
                objLead.Page_2_Completed_Date__c = datetime.now();
            }
            // WF-28-Check Singapore IB CP 
            if((oldMap.get(objLead.id).Entity__c != objLead.Entity__c || oldMap.get(objLead.id).LeadSource != objLead.LeadSource || oldMap.get(objLead.id).IB_ID__c != objLead.IB_ID__c) && (objLead.Entity__c == 'Singapore-AD' && (objLead.LeadSource == 'Client-Portal-Lead-Cn' || objLead.LeadSource == 'Client-Portal-Live-Cn') && objLead.IB_ID__c!= null && objLead.IB_ID__c.contains('ads')))
            {
                objLead.Notify__c = true;
            } 
            
            // WF-29-Contacted_LeadStatus to Warm_LeadRating
            if((oldMap.get(objLead.id).Status != objLead.Status) && (objLead.Status == 'Contacted 1' || objLead.Status == 'Contacted 2' || objLead.Status == 'Contacted 3'))
            {
                objLead.Rating = 'Warm';
            }
            
            // WF-30-Risk Category Update
            if(objLead.Total_KYC_Risk_Score__c != null)
            {
                if(objLead.Total_KYC_Risk_Score__c <= 4.00)
                {
                    objLead.Risk_Category__c = 'Low';
                }
                else if(objLead.Total_KYC_Risk_Score__c > 4.00 && objLead.Total_KYC_Risk_Score__c <= 8.00)
                {
                    objLead.Risk_Category__c = 'Medium';
                }
                else if(objLead.Total_KYC_Risk_Score__c > 8.00 && objLead.Total_KYC_Risk_Score__c <= 12.00)
                {
                    objLead.Risk_Category__c = 'High';
                }else
                {
                    ObjLead.Risk_Category__c = 'Fail';
                }
            }
            /* // WF-31-Update Time Stamp Sent for Approval
            if(objLead.Status == 'Pending CS Team Approval' )
            {
                objLead.Time_duration_Create_Lead_Sent_For_App__c = DateTime.now() - objLead.CreatedDate;
            } */
            
            // WF-32-Lead Next Action Copy-LDN
            if((oldMap.get(objLead.id).Action__c != objLead.Action__c) && (objLead.Action__c == 'Call 1' || objLead.Action__c == 'Call 2' || objLead.Action__c == 'Call 3' || objLead.Action__c == 'Call 4' || objLead.Action__c == 'Call 5' || objLead.Action__c == 'Call 6' || objLead.Action__c == 'Call 7'))
            {
                objLead.Next_Action_copy__c = objLead.Next_Action__c;
            }
                
            /* Author : Ashish Pandey
            Description :  STP Check-If any modification is done by Sales profile user on Lead record, it will check "Non STP" checkbox on Lead.      */           
            if(system.label.STPCheck.contains('True')) 
            {               
                if(System.Label.STPProfiles.contains(profileName))
                {
                    system.debug('===>> '+objLead.Last_Modified_by_Profile__c);
                    if(Trigger.newmap != Trigger.oldmap && objLead.Non_STP_Check__c == false && objLead.Entity__c != 'London Retail')
                    {
                        objLead.Non_STP_Check__c = True;
                    }   
                    if(objLead.SalesActivityCounter__c == 1)
                    {
                        if(objLead.Entity__c == 'London Retail')
                        {
                            objLead.Non_STP_Check__c = True;
                        }
                        objLead.First_Activity_Created_Date__c = dateTime.now();
                        objLead.First_Activity_Created_By__c = mapUserIDtoName.get(UserInfo.getUserId());
                    }   
                }
            }
            
            //ADS Global Instituional - Liduidity Profile check
            
            if(objLead.RecordTypeID == System.label.ADSGlobalInstitutionalLeadRT && objLead.Liquidity_Bucket_Profile__c == null && objLead.Institutional_Approval_Stage__c == System.Label.LiquidityApprovedOPSPending)
            {
                objLead.addError('Please fill Liquidity Profile before proceeding');
            }
            
           /*  if((oldMap.get(objLead.id).IBPortalID__c != objLead.IBPortalID__c) && oldMap.get(objLead.id).IBPortalID__c == null && objLead.IBPortalID__c >0){
                objLead.IB_Portal_Insert__c = false;                
            }
            if((objLead.IBPortalID__c != null && objLead.IBPortalID__c > 0) && ((oldMap.get(objLead.id).Name != objLead.Name ) || (oldMap.get(objLead.id).Email != objLead.Email) || (oldMap.get(objLead.id).Phone != objLead.Phone) || (oldMap.get(objLead.id).Entity__c != objLead.Entity__c) || (oldMap.get(objLead.id).Country_of_Residence__c != objLead.Country_of_Residence__c) || (oldMap.get(objLead.id).IB_ID__c != objLead.IB_ID__c))){
                objLead.IB_Portal_Update__c = true;
            } */
            if(objLead.HasOptedOutOfEmail == oldMap.get(objLead.id).HasOptedOutOfEmail)
            {
                if((objLead.Educational_Marketing_Email__c == False && objLead.Market_News_Marketing_Email__c == False&& objLead.Products_Services_Marketing_Email__c  == False && objLead.ResearchEmailRequest_First_Call__c  == False && objLead.ResearchEmailRequest_Morning_Brief__c == False && 
                objLead.ResearchEmailRequest_Pre_Asia_FX__c == False && objLead.ResearchEmailRequest_Pre_Asia_CFD__c == False && objLead.ResearchEmailRequest_Pre_USA_FX__c == False && objLead.ResearchEmailRequest_Pre_USA_CFD__c == False && objLead.ResearchEmailRequest_Pre_European_FX__c == False && objLead.ResearchEmailRequest_Pre_European_CFD__c == False) && (objLead.Educational_Marketing_Email__c != oldMap.get(objLead.id).Educational_Marketing_Email__c || objLead.Market_News_Marketing_Email__c != oldMap.get(objLead.id).Market_News_Marketing_Email__c || objLead.Products_Services_Marketing_Email__c != oldMap.get(objLead.id).Products_Services_Marketing_Email__c || objLead.ResearchEmailRequest_First_Call__c != oldMap.get(objLead.id).ResearchEmailRequest_First_Call__c || objLead.ResearchEmailRequest_Morning_Brief__c != oldMap.get(objLead.id).ResearchEmailRequest_Morning_Brief__c || objLead.ResearchEmailRequest_Pre_Asia_FX__c != oldMap.get(objLead.id).ResearchEmailRequest_Pre_Asia_FX__c || objLead.ResearchEmailRequest_Pre_Asia_CFD__c != oldMap.get(objLead.id).ResearchEmailRequest_Pre_Asia_CFD__c || objLead.ResearchEmailRequest_Pre_USA_FX__c != oldMap.get(objLead.id).ResearchEmailRequest_Pre_USA_FX__c || objLead.ResearchEmailRequest_Pre_USA_CFD__c != oldMap.get(objLead.id).ResearchEmailRequest_Pre_USA_CFD__c || objLead.ResearchEmailRequest_Pre_European_FX__c != oldMap.get(objLead.id).ResearchEmailRequest_Pre_European_FX__c || objLead.ResearchEmailRequest_Pre_European_CFD__c != oldMap.get(objLead.id).ResearchEmailRequest_Pre_European_CFD__c) || objLead.HasOptedOutOfEmail == True)
                {
                    objLead.HasOptedOutOfEmail = True;
                }
                else{
                    objLead.HasOptedOutOfEmail = False;
                }
            } 
            
            
        }
        for(Account objAcc:[select id,OwnerID,Owner.IsActive,Referral_Code_ID__c from Account where Referral_Code_ID__c IN:setReferralID and Owner.IsActive = true]){
            MapReferralCodeandOwnerId.put(objAcc.Referral_Code_ID__c,objAcc.OwnerID);
        }
        for(Lead objLead : (List<Lead>)Trigger.new){
            if(MapReferralCodeandOwnerId.get(objLead.Referred_By__c) != null)
                objLead.Referral_Owner__c = MapReferralCodeandOwnerId.get(objLead.Referred_By__c);
        }       
        if(lstHT.size()>0)
            insert lstHT;
        if(lstCampaignMember != null && lstCampaignMember.size()>0){
            Database.SaveResult[] srList = Database.insert(lstCampaignMember,false);
        }        
    }  
    
    /*  Author : Ashish Pandey
        Description : It maps the IB-ID field value from lead to the corresponding IB-ID Code field on platform Account object and pushes the IB Name account from "Platform Account" object to Lead's IB Name field */
    
    public void IBNameToIBCode(String DMLType)
    {
        set<ID> setId = new Set<ID>();
        set<String> setString = new set<String>();
        List<Lead> lstLead = new List<Lead>();
        Map<String, String> mapPlatformAccount = new Map<String, String>();
        Map<String, Id> mappAccName_Owner = new Map<String, Id>();
        if(DMLType == 'insert')
        {
            for(Lead ld : (List<Lead>)Trigger.new)
            {
                if(ld.IB_ID__c!= '' && ld.IB_ID__c!= null)
                {
                    if(ld.IB_ID__c.contains('-') )
                    {
                        setString.add(ld.IB_ID__c.subStringBefore('-'));
                    }
                    else if(ld.IB_ID__c.length()<11 && !ld.IB_ID__c.contains('-'))
                    {
                        setString.add(ld.IB_ID__c);
                    }
                }  
            }
        }
        if(DMLType == 'update')
        {
            for(Lead ld : (List<Lead>)Trigger.new)
            {
                Lead oldLead = (Lead)trigger.oldMap.get(ld.Id);
                if(ld.IB_ID__c!= '' && ld.IB_ID__c!= null && oldLead.IB_ID__c != ld.IB_ID__c)
                {
                    if(ld.IB_ID__c.contains('-') )
                    {
                        setString.add(ld.IB_ID__c.subStringBefore('-'));
                    }
                    else if(ld.IB_ID__c.length()<11 && !ld.IB_ID__c.contains('-'))
                    {
                        setString.add(ld.IB_ID__c);
                    }
                }  
            }
        }
        if(!setString.isEmpty())
        {
            system.debug('---> '+ setString);
            for(ADSS_Platform_Account__c platAccount : [Select id,name, IB_ID__c, IB_ID_CODE__c, IB_Name__c, OwnerId, owner.name, Owner.isActive from ADSS_Platform_Account__c where IB_ID_CODE__c in: setString])
            {
                mapPlatformAccount.put(platAccount.IB_ID_CODE__c, platAccount.IB_Name__c);
            }
            
            for(ADSS_Platform_Account__c pAccount : [Select id, name, OwnerId, owner.name, Owner.isActive from ADSS_Platform_Account__c where name in: setString])
            {
                if(pAccount.Owner.isActive == true)
                {
                    mappAccName_Owner.put(pAccount.name, pAccount.OwnerId);
                }
            }
            
            try
            {           
                for(Lead ld : (List<Lead>)Trigger.new)
                {
                    if(ld.IB_ID__c!= '' && ld.IB_ID__c!= null )
                    {
                        if(ld.IB_ID__c.contains('-') )
                        {
                            if(mapPlatformAccount.containsKey(ld.IB_ID__c.subStringBefore('-')) )
                            {
                                ld.IB_Name__c = mapPlatformAccount.get(ld.IB_ID__c.subStringBefore('-'));
                            }
                            if(DMLType == 'insert'){
                                if(mappAccName_Owner.containsKey(ld.IB_ID__c.subStringBefore('-')))
                                {
                                    ld.IB_Account_Owner__c = mappAccName_Owner.get(ld.IB_ID__c.subStringBefore('-'));
                                }
                                else
                                {
                                    ld.IB_Account_Owner__c = UserInfo.getUserID();
                                }
                            }
                        }
                        else if(ld.IB_ID__c.length()<11 && !ld.IB_ID__c.contains('-'))  
                        {           
                            if(mappAccName_Owner.containsKey(ld.IB_ID__c) )
                            {
                                ld.IB_Name__c = mapPlatformAccount.get(ld.IB_ID__c);
                            }
                            if(DMLType == 'insert'){
                                if(mappAccName_Owner.containsKey(ld.IB_ID__c))
                                {
                                    ld.IB_Account_Owner__c = mappAccName_Owner.get(ld.IB_ID__c);
                                }
                                else
                                {
                                    ld.IB_Account_Owner__c = UserInfo.getUserID();
                                }
                            }
                        }
                    }   
                }
            }
            catch(Exception e)
            {                
            }            
        }
    }
      
     /*  Author : Ashish Pandey
         Description : Check Lead duplicity based on Email and Phone Number on insert and edit, and creates new CR record with existing Lead  */
     
    public void checkDuplicates(String DMLType)
    {
        Set<String> setEmail = new Set<String>();
        Set<String> setPhone = new Set<String>();    
        List<Lead> lstLead = new List<lead>();
        List<Lead> lstDelLead = new List<lead>();
        List<Lead> lstLeadsUTMUpdate = new List<Lead>();
        List<Contact> lstContactUTMUpdate = new List<Contact>();
        List<Contact> lstContact = new List<Contact>();
        List<Clients_Registration_Details__c > lstCR = new List<Clients_Registration_Details__c >();        
        Map<id,Lead> newLeadMap = (Map<id,Lead>)Trigger.newMap;
        Map<String, Lead> mapEmailPhoneLead = new Map<String, Lead>();
        Map<String, Contact> mapEmailPhoneContact = new Map<String, Contact>();
        List<Blacklist_Client__c> lstBlackListClient = new List<Blacklist_Client__c>();
        if(DMLType == 'insert')
        {
            for(Lead objLd : (List<Lead>)trigger.new){
                if(objLd.email != null && objLd.email != ''){
                    setEmail.add(objLd.email);
                }
                if(objLd.Phone != null && objLd.Phone != ''){
                    setPhone.add(objLd.Phone);
                }
            }
        }
        else if(DMLType == 'update')
        {
            Map<id,Lead> oldLeadMap = (Map<id,Lead>)Trigger.oldMap;
             for(Lead objLd : (List<Lead>)trigger.new)
             {
                Lead oldLead = (Lead)Trigger.oldMap.get(objLd.id);                
                if(objLd.email != null && objLd.email != '' && objLd.email != oldLead.email){
                    setEmail.add(objLd.email);
                }                
                if(objLd.Phone != null && objLd.Phone != '' && oldLead.Phone != '' && oldLead.Phone != null && objLd.Phone.length() >= 8 && oldLead.Phone.length() >= 8)
                {
                    if(objLd.Phone.Right(8) != oldLead.Phone.Right(8)){
                        setPhone.add(objLd.Phone);
                    }
                }
                else if(objLd.Phone != null && objLd.Phone != '' && oldLead.Phone != objLd.Phone){
                    setPhone.add(objLd.Phone);
                }
            }
        }
               
        if(setEmail.size() > 0 || setPhone.size() > 0){
            lstLead = [Select id, email, Phone,OwnerId,Owner.IsActive,utm_campaign__c,utm_source__c,Campaign_Tracking__c from Lead where (email in: setEmail OR phone in: setPhone) and isConverted = false];
            lstContact = [Select id, email, AccountId, phone,OwnerId,Owner.IsActive,utm_campaign__c,utm_source1__c,CampaignTracking__c from Contact where (email in: setEmail OR phone in: setPhone)];
            lstBlackListClient = [Select id, Email__c, Phone__c from Blacklist_Client__c where (Email__c in: setEmail OR Phone__c in: setPhone)];
            if(lstLead.size() > 0){
                for(lead ObjLd : lstLead){
                    if(ObjLd.Email != null && ObjLd.Email != ''){
                        mapEmailPhoneLead.put(objLd.email.tolowerCase(), ObjLd);
                    }
                    if(objLd.Phone != null && ObjLd.Phone != ''){
                        mapEmailPhoneLead.put(objLd.phone, ObjLd);
                    }
                }
            }
            if(lstContact.size() > 0){
                for(Contact ObjCon : lstContact){
                    if(ObjCon.Email != null && ObjCon.Email != ''){
                        mapEmailPhoneContact.put(ObjCon.email.tolowerCase(), ObjCon);
                    }
                    if(ObjCon.Phone != null && ObjCon.Phone != ''){
                        mapEmailPhoneContact.put(ObjCon.phone, ObjCon);
                    }
                }
            }
            for(Lead ldobj : (List<Lead>)trigger.new)
            {
                if(lstBlackListClient.size()>0)
                {
                    ldobj.Blacklist_Client__c = TRUE;
                }
                else
                {
                    ldobj.Blacklist_Client__c = FALSE;
                }
            }
        }
    
        for(Lead objLd : (List<Lead>)Trigger.new)
        {
            if(objLd.email != null && objLd.email != ''){
                objLd.email = objLd.email.tolowerCase();
            }
            if(mapEmailPhoneLead.containsKey(objLd.email) || mapEmailPhoneLead.containsKey(objLd.phone) || mapEmailPhoneContact.containsKey(objLd.email) || mapEmailPhoneContact.containsKey(objLd.phone))
            {
                Clients_Registration_Details__c objCR = new Clients_Registration_Details__c();
                objCR.Name=objLd.firstname+' '+objLd.lastname;
                objCR.Campaign_Tracking__c=objLd.Campaign_Tracking__c;
                objCR.Country_of_Residence__c=objLd.Country_of_Residence__c;
                objCR.email__c=objLd.email;
                objCR.Entity__c=objLd.Entity__c;
                objCR.IB_ID__c=objLd.IB_ID__c;
                objCR.Lead_Source__c=objLd.leadsource;
                objCR.mobile__c=objLd.phone;
                objCR.Is_Duplicate__c = true; 
                objCR.Inserted_by__c = UserInfo.getUserId();
                objCR.utm_campaign__c= objLd.utm_campaign__c;
                objCR.utm_source__c= objLd.utm_source__c;
                        
                if(objLd.email != null && objLd.email != '' && mapEmailPhoneContact.containsKey(objLd.email) && mapEmailPhoneContact.get(objLd.email)!= null){
                    objCR.Account_Name__c = mapEmailPhoneContact.get(objLd.email).AccountId;
                    objCR.Contact__c = mapEmailPhoneContact.get(objLd.email).Id;
                        if(mapEmailPhoneContact.get(objLd.email).Owner.IsActive && String.valueOf(mapEmailPhoneContact.get(objLd.email).Ownerid).startswith('005'))
                        {
                            objCR.Existing_Lead_Contact_Owner__c=mapEmailPhoneContact.get(objLd.email).OwnerId;
                            objCR.ownerID = mapEmailPhoneContact.get(objLd.email).OwnerId;
                        }
                        else
                        {
                            objCR.Existing_Lead_Contact_Owner__c=System.label.IntegrationUserID;
                            objCR.OwnerID = System.label.IntegrationUserID;
                        }
                    Contact objCon = mapEmailPhoneContact.get(objLd.email);
                    Boolean blnUTM = false;
                    if(mapEmailPhoneContact.get(objLd.email).utm_campaign__c != objLd.utm_campaign__c && objLd.utm_campaign__c != null && objLd.utm_campaign__c != ''){                   
                        objCon.utm_campaign__c = objLd.utm_campaign__c;
                        blnUTM = true;
                    }
                    if(mapEmailPhoneContact.get(objLd.email).CampaignTracking__c != objLd.Campaign_Tracking__c && objLd.Campaign_Tracking__c != null && objLd.Campaign_Tracking__c != ''){            
                        objCon.CampaignTracking__c = objLd.Campaign_Tracking__c;                        
                        blnUTM = true;
                    }
                    if(mapEmailPhoneContact.get(objLd.email).utm_source1__c != objLd.utm_source__c && objLd.utm_source__c != null && objLd.utm_source__c != ''){                   
                        objCon.utm_source1__c = objLd.utm_source__c;
                        blnUTM = true;
                    }
                    if(blnUTM == true)
                        lstContactUTMUpdate.add(objCon);
                }
                else if(objLd.phone != null && objLd.phone != '' && mapEmailPhoneContact.containsKey(objLd.phone) && mapEmailPhoneContact.get(objLd.phone)!= null){
                    objCR.Account_Name__c = mapEmailPhoneContact.get(objLd.phone).AccountId;
                        if(mapEmailPhoneContact.get(objLd.phone).Owner.IsActive && String.valueOf(mapEmailPhoneContact.get(objLd.phone).Ownerid).startswith('005'))
                        {
                            objCR.Existing_Lead_Contact_Owner__c=mapEmailPhoneContact.get(objLd.phone).OwnerId;
                            objCR.ownerID = mapEmailPhoneContact.get(objLd.phone).OwnerId;
                        }
                        else
                        {
                            objCR.Existing_Lead_Contact_Owner__c=System.label.IntegrationUserID;
                            objCR.OwnerID = System.label.IntegrationUserID;
                        }                       
                    Contact objCon = mapEmailPhoneContact.get(objLd.phone);
                    Boolean blnUTM1 = false;
                    if(mapEmailPhoneContact.get(objLd.phone).utm_campaign__c != objLd.utm_campaign__c && objLd.utm_campaign__c != null && objLd.utm_campaign__c != ''){                      
                        objCon.utm_campaign__c = objLd.utm_campaign__c;
                        blnUTM1 = true;
                    }
                    if(mapEmailPhoneContact.get(objLd.phone).CampaignTracking__c != objLd.Campaign_Tracking__c && objLd.Campaign_Tracking__c != null && objLd.Campaign_Tracking__c != ''){              
                        objCon.CampaignTracking__c = objLd.Campaign_Tracking__c;
                        blnUTM1 = true;
                    }
                    if(mapEmailPhoneContact.get(objLd.phone).utm_source1__c != objLd.utm_source__c && objLd.utm_source__c != null && objLd.utm_source__c != ''){                      
                        objCon.utm_source1__c = objLd.utm_source__c;
                        blnUTM1 = true;
                    }
                    if(blnUTM1 == true)
                        lstContactUTMUpdate.add(objCon);
                }
                else if(objLd.email != null && objLd.email != '' && mapEmailPhoneLead.containsKey(objLd.email) && mapEmailPhoneLead.get(objLd.email)!= null){
                    objCR.Lead_Name__c = mapEmailPhoneLead.get(objLd.email).id;
                       if(mapEmailPhoneLead.get(objLd.email).Owner.IsActive && String.valueOf(mapEmailPhoneLead.get(objLd.email).Ownerid).startswith('005'))
                       {
                            objCR.Existing_Lead_Contact_Owner__c=mapEmailPhoneLead.get(objLd.email).OwnerId;
                            objCR.ownerID = mapEmailPhoneLead.get(objLd.email).OwnerId;
                       }
                       else
                       {
                            objCR.Existing_Lead_Contact_Owner__c=System.label.IntegrationUserID;
                            objCR.OwnerID = System.label.IntegrationUserID;
                       }
                    Lead objLead = mapEmailPhoneLead.get(objLd.email);
                    Boolean blnUTMLead = false;
                    if(mapEmailPhoneLead.get(objLd.email).utm_campaign__c != objLd.utm_campaign__c && objLd.utm_campaign__c != null && objLd.utm_campaign__c != ''){                
                        objLead.utm_campaign__c = objLd.utm_campaign__c;
                        blnUTMLead = true;
                    }
                    if(mapEmailPhoneLead.get(objLd.email).Campaign_Tracking__c != objLd.Campaign_Tracking__c && objLd.Campaign_Tracking__c != null && objLd.Campaign_Tracking__c != ''){
                        objLead.Campaign_Tracking__c = objLd.Campaign_Tracking__c;
                        blnUTMLead = true;
                    }
                    if(mapEmailPhoneLead.get(objLd.email).utm_source__c != objLd.utm_source__c && objLd.utm_source__c != null && objLd.utm_source__c != ''){                
                        objLead.utm_source__c = objLd.utm_source__c;
                        blnUTMLead = true;
                    }
                    if(blnUTMLead == true)
                        lstLeadsUTMUpdate.add(objLead);
                }
                else if(objLd.phone != null && objLd.phone != '' && mapEmailPhoneLead.containsKey(objLd.phone) && mapEmailPhoneLead.get(objLd.phone)!= null){
                    objCR.Lead_Name__c = mapEmailPhoneLead.get(objLd.phone).id;
                        if(mapEmailPhoneLead.get(objLd.phone).Owner.IsActive && String.valueOf(mapEmailPhoneLead.get(objLd.phone).Ownerid).startswith('005') )
                        {
                            objCR.Existing_Lead_Contact_Owner__c=mapEmailPhoneLead.get(objLd.phone).OwnerId;
                            objCR.ownerID = mapEmailPhoneLead.get(objLd.phone).OwnerId;
                        }
                        else
                        {
                            objCR.Existing_Lead_Contact_Owner__c=System.label.IntegrationUserID;
                            objCR.OwnerID = System.label.IntegrationUserID;
                        }
                    Lead objLead = mapEmailPhoneLead.get(objLd.phone);
                    Boolean blnUTMLead1 = false;
                    if(mapEmailPhoneLead.get(objLd.phone).utm_campaign__c != objLd.utm_campaign__c && objLd.utm_campaign__c != null && objLd.utm_campaign__c != ''){                     
                        objLead.utm_campaign__c = objLd.utm_campaign__c;
                        blnUTMLead1 = true;
                    }
                    if(mapEmailPhoneLead.get(objLd.phone).Campaign_Tracking__c != objLd.Campaign_Tracking__c && objLd.Campaign_Tracking__c != null && objLd.Campaign_Tracking__c != ''){
                        objLead.Campaign_Tracking__c = objLd.Campaign_Tracking__c;
                        blnUTMLead1 = true;
                    }
                    if(mapEmailPhoneLead.get(objLd.phone).utm_source__c != objLd.utm_source__c && objLd.utm_source__c != null && objLd.utm_source__c != ''){                     
                        objLead.utm_source__c = objLd.utm_source__c;
                        blnUTMLead1 = true;
                    }
                    if(blnUTMLead1 == true)
                        lstLeadsUTMUpdate.add(objLead);
                }
                lstCR.add(objCR);                
                objLd.Is_Duplicate__c = true;
                objLd.ByPass_AS__c = true;
                objLd.status = 'Duplicate Lead';
            }   
        }
        if(lstCR != null && lstCR.size()>0)
            insert lstCR;
        if(lstLeadsUTMUpdate != null && lstLeadsUTMUpdate.size()>0)
            update lstLeadsUTMUpdate;
        if(lstContactUTMUpdate != null && lstContactUTMUpdate.size()>0)
            update lstContactUTMUpdate;
    }
    
    /* Author :  Ashish Pandey
       Description : Deleting the list of Leads, which are duplicate */
    
    public void afterInsertMethod()
    {
        Set<Id> leadIds = new Set<Id>();      
        List<CampaignMember> lstCampaignMember = new List<CampaignMember>();
        Map<string,id> mapUTMCampaignandID = new map<string,id>();
        set<id> convertedleadids = new set<id>();
        list<Opportunity> opplist = new list<Opportunity>();
        list<Case> caselist = new list<Case>();
        list<Contacts_List__c> conlist = new list<Contacts_List__c>();
        Map<id,id> mapLeadandAccountID = new map<id,id>(); 
            
        for(Campaign camp :[select id,utmcampaign__c,utmsource__c,RecordTypeId,IsActive,Auto_Campaign_Member_Creation__c from Campaign where (RecordTypeId =: System.Label.Monthly_Campaign or RecordTypeId =: System.Label.Seminars or RecordTypeId =: System.Label.UTM_Source) and (utmcampaign__c != null or utmsource__c != null)  and IsActive = true and Auto_Campaign_Member_Creation__c = true]){
            if(camp.utmcampaign__c != null)
                mapUTMCampaignandID.put(camp.utmcampaign__c,camp.id);
            else if(camp.utmsource__c != null)
                mapUTMCampaignandID.put(camp.utmsource__c,camp.id);
        }
        for(Lead objLd : (List<Lead>)Trigger.new){
                    
            if(objLd.Is_Duplicate__c){
                leadIds.add(objLd.id);
            }
            if(objLd.utm_campaign__c != '' && objLd.utm_campaign__c != null){       
                if(mapUTMCampaignandID.get(objLd.utm_campaign__c) != null){     
                    CampaignMember objCamMember = new CampaignMember();     
                    objCamMember.CampaignID = mapUTMCampaignandID.get(objLd.utm_campaign__c);       
                    objCamMember.LeadId = objLd.Id;     
                    objCamMember.MemberAddedby__c = 'Automated Entry';      
                    lstCampaignMember.add(objCamMember);        
                }
            }
            if(objLd.utm_source__c != '' && objLd.utm_source__c != null){       
                if(mapUTMCampaignandID.get(objLd.utm_source__c) != null){     
                    CampaignMember objCamMember = new CampaignMember();     
                    objCamMember.CampaignID = mapUTMCampaignandID.get(objLd.utm_source__c);       
                    objCamMember.LeadId = objLd.Id;     
                    objCamMember.MemberAddedby__c = 'Automated Entry';      
                    lstCampaignMember.add(objCamMember);        
                }
            }
            if((objLd.LeadSource == 'Prime-Web-Live-Cn' && !Approval.isLocked(objLd.id)) || ((objLd.LeadSource == 'Manual entry' || objLd.LeadSource == 'Prime-Web-Live-Ar' || objLd.LeadSource == 'Prime-Web-Live' || objLd.LeadSource == 'Web-Live' || objLd.LeadSource == 'Web-Live-Application'  || objLd.LeadSource == 'Prime-Web-Lite-Ad' || 
                objLd.LeadSource == 'Prime-Web-Lite-Ad-Ar' || objLd.LeadSource == 'Prime-Web-Demo-Ar' || objLd.LeadSource == 'Prime-Web-Demo' || objLd.LeadSource == 'Prime-Web-Ad-Ar' || objLd.LeadSource == 'Prime-Web-Ad' || objLd.LeadSource == 'Prime-Web-Lite-Live' || objLd.LeadSource == 'Prime-Web-Lite-Live-Ar' || 
                objLd.LeadSource == 'Prime-Web-Lite-Demo' || objLd.LeadSource  == 'Prime-Web-Lite-Demo-Ar' || objLd.LeadSource == 'Web-Professional') && objLd.Compliance_Status__c == 'Waiting Approval' && !Approval.isLocked(objLd.id) && 
                (objLd.Application_type__c == 'Individual Trading Account' || objLd.Application_type__c == 'Joint Trading Account'))){
                    try{
                        Approval.ProcessSubmitRequest app = new Approval.ProcessSubmitRequest();
                        app.setObjectId(objLd.id);
                        Approval.ProcessResult result = Approval.process(app);
                    }
                    catch(Exception e){
                    System.debug('>>>>>Error: '+e.getMessage());
                    }
            }
            
            //below code will reparent opportunities and cases to account created
            if(objLd.IsConverted){
                convertedleadids.add(objLd.id);
                mapLeadandAccountID.put(objLd.id,objLd.Converted_Lead_Account_ID__c);
            }   
        
            
        }
                        
        List<ProcessInstance> lstPI = [SELECT Id,Status,LastActorId,TargetObjectId,ProcessDefinition.Name,(SELECT Id,StepStatus,Comments,ActorId,SystemModstamp FROM Steps order by SystemModstamp DESC) FROM ProcessInstance where TargetObjectId in : convertedleadids];  
        List<Approval_Tracking__c> lstAT = new list<Approval_Tracking__c>();
        for(ProcessInstance objPI : lstPI){
            for(ProcessInstanceStep objPIS : objPI.Steps){
                if(objPIS.StepStatus == 'Approved' || objPIS.StepStatus == 'Rejected'){
                    Approval_Tracking__c objAT = new Approval_Tracking__c();
                    objAT.Status__c = objPIS.StepStatus;
                    objAT.Approved_Rejected_By__c = objPIS.ActorId;
                    objAT.Comments__c = objPIS.Comments;
                    objAT.Approval_Rejection_Time__c = objPIS.SystemModstamp;
                    objAT.Approval_Step_Name__c = objPI.ProcessDefinition.Name;
                    objAT.Account__c = mapLeadandAccountID.get(objPI.TargetObjectId);
                    lstAT.add(objAT);
                }
            }
        }
        if(lstAT.size()>0)
            insert lstAT;
        
        opplist = [select Lead_del__c, Lead_del__r.ConvertedAccountId, AccountId from Opportunity where Lead_del__c in : convertedleadids];  
        list<Opportunity> updateopps = new list<Opportunity>();
        for(Opportunity opp: opplist){
            opp.AccountId= opp.Lead_del__r.ConvertedAccountId;
            //opp.Lead_del__c = null;
            updateopps.add(opp);
        }
        if(updateopps.size()>0 && updateopps != null)
            update updateopps;

        // on all cases after lead conversion it is related to account or contact    
        caselist = [select Lead_Name__c, Lead_Name__r.ConvertedAccountId, Lead_Name__r.ConvertedContactId , AccountId from Case where Lead_Name__c in : convertedleadids];
        list<Case> updatecases = new list<Case>();
        for(Case cs: caselist){
            cs.AccountId= cs.Lead_Name__r.ConvertedAccountId;
            cs.ContactId= cs.Lead_Name__r.ConvertedContactId ;
            //cs.Lead_Name__c = null;
            updatecases.add(cs);
        }
        if(updatecases.size()>0 && updatecases != null)
            update updatecases;

        conlist = [Select Lead_Name__c, Lead_Name__r.ConvertedAccountId from Contacts_List__c WHERE Lead_Name__c in : convertedleadids];
        list<Contacts_List__c> conlistupdate = new list<Contacts_List__c>();
        for(Contacts_List__c con: conlist){
            con.Account_Name__c = con.Lead_Name__r.ConvertedAccountId;
            conlistupdate.add(con);
        }
        if(conlistupdate.size()>0 && conlistupdate!= null)
            update conlistupdate;   
            
        if(lstCampaignMember != null && lstCampaignMember.size()>0){        
            Database.SaveResult[] srList = Database.insert(lstCampaignMember,false);
        }
        DeleteDuplicates.Duplicate_Lead_Dletion(leadIds);
        //LeadAutoAssignmentClass.Lead_Auto_Reassign(setKenticoLeads);
        
    }
    
    /* Author : Ashish Pandey 
       Description : Checks whether a Call has been logged, before changing the sstauts of the Lead.   */
    
    public void afterUpdateMethod(List<Lead> TriggerList)
    {
        set<ID> ldCount = new set<ID>();
        Map<ID,ID> countLeadAct = new  Map<ID,ID>();
        Id id1 = UserInfo.getProfileId();
        String profileName = [Select Id,Name from Profile where Id=:id1].Name;
        if(profileName == 'Sales VP' || profileName == 'Sales Prime' )
        {
            For(Lead ld:TriggerList)
            {
                Lead oldLeadValue = (Lead)Trigger.oldMap.get(ld.id);
                if(ld.Status != oldLeadValue.Status )
                {
                    ldCount.add(ld.ID);
                }
            }
            if(!ldCount.isEmpty())
            {
                DateTime currentTime = system.now();
                DateTime timePast = currentTime.addHours(-24);                         
                For(Task actHistory:[select id, subject, who.name, lastModifiedDate,CreatedDate from Task where whoId in: ldCount AND Subject LIKE '%Call%' AND (CreatedDate <: currentTime AND CreatedDate >: timePast)])
                {
                    countLeadAct.put(actHistory.WhoId,actHistory.id);
                }
            }
            For(Lead ld:TriggerList)
            {
                Lead oldLeadValue = (Lead)Trigger.oldMap.get(ld.id);                
                ID leadActID = countLeadAct.get(ld.id);                                  
                if(ld.Status != oldLeadValue.Status && leadActID == null && ld.OwnerID == UserInfo.getUserId() )//&& (ld.Owner.Profile.Name == 'Sales VP' || ld.Owner.Profile.Name == 'Sales Prime'))
                {
                    ld.addError('Before changing the Lead Status, please Log A Call within a 24-hour period.');
                }
            }
        }
    }
    public void riskCalculation_MIFID(List<Lead> lstLead)
    {
        Map<String, String> mapLeadCountrytoRiskCountry = new Map<String, String>();
        Map<String, Risk_Countries__c> mapNametoCountryMapping = new Map<String, Risk_Countries__c>();
        
        for(Risk_Countries__c objCountry : [select id, name, Country_of_Residence__c, Country_CI__c, Country_EEA__c, Country_FATF__c, Country_Region__c, Country_Risk_Level__c, Document_Requirement__c, 
                                            Country_FATF_EEA_Score__c,Country_CI_Score__c,Entity__c, Calling_Code__c from Risk_Countries__c])
        {
            mapNametoCountryMapping.put(objCountry.Country_of_Residence__c, objCountry) ;
        } 

        for(Lead objLd : lstLead)
        {
            if(String.valueOf(objLd.OwnerId).startswith('005') && System.Label.ADSSKenticoUserID.contains(objLd.OwnerID))
            {
                if(mapNametoCountryMapping.containsKey(objLd.Country_of_Residence__c))
                {
                    objLd.Entity__c = mapNametoCountryMapping.get(objLd.Country_of_Residence__c).Entity__c;
                }
            }
            if(objLd.recordTypeId == System.Label.ADS_Lead_LondonRetail_RecordTypeID)
            {
                if(mapNametoCountryMapping.containsKey(objLd.Country_of_Residence__c))
                {
                    system.debug('--->> ' + mapNametoCountryMapping);   
                    objLd.MiFID_Risk_Country__c = mapNametoCountryMapping.get(objLd.Country_of_Residence__c).id;
                    objLd.MiFID_Country_FATF_EEA_Score__c = mapNametoCountryMapping.get(objLd.Country_of_Residence__c).Country_FATF_EEA_Score__c;
                    objLd.MiFID_Country_CI_Score__c = mapNametoCountryMapping.get(objLd.Country_of_Residence__c).Country_CI_Score__c;
                }
                if(objLd.secondary_Nationality__c != null && objLd.secondary_Nationality__c != '')
                {
                    if(objLd.Nationality__c != null && objLd.Nationality__c != '')
                    {
                        if(mapNametoCountryMapping.containsKey(objLd.Nationality__c) && mapNametoCountryMapping.containsKey(objLd.secondary_Nationality__c))
                        {
                            if(mapNametoCountryMapping.get(objLd.Nationality__c).Country_EEA__c == true && mapNametoCountryMapping.get(objLd.secondary_Nationality__c).Country_EEA__c == false)
                                objLd.Preferred_Nationality__c = objLd.Nationality__c;
                            else if(mapNametoCountryMapping.get(objLd.Nationality__c).Country_EEA__c == false && mapNametoCountryMapping.get(objLd.secondary_Nationality__c).Country_EEA__c == true)
                                objLd.Preferred_Nationality__c = objLd.secondary_Nationality__c;
                            else{
                                List<string> lstNatstr = new list<string>();                            
                                String strNat1 = objLd.Nationality__c;
                                String strNat2 = objLd.secondary_Nationality__c;
                                lstNatstr.add(strNat1);
                                lstNatstr.add(strNat2);
                                lstNatstr.sort();
                                objLd.Preferred_Nationality__c = lstNatstr[0];                  
                            }
                        }   
                    }
                }
                else if(objLd.Nationality__c != null && objLd.Nationality__c != '')
                {
                    objLd.Preferred_Nationality__c = objLd.Nationality__c;
                }                    
                if(mapNametoCountryMapping.containsKey(objLd.Preferred_Nationality__c)){
                    objLd.MiFID_NationalityCI__c = mapNametoCountryMapping.get(objLd.Preferred_Nationality__c).Country_CI__c;
                    objLd.MiFID_NationalityEEA__c = mapNametoCountryMapping.get(objLd.Preferred_Nationality__c).Country_EEA__c;
                    objLd.MiFID_NationalityFATF__c = mapNametoCountryMapping.get(objLd.Preferred_Nationality__c).Country_FATF__c;
                    objLd.MiFID_Nationality_Risk_Level__c = mapNametoCountryMapping.get(objLd.Preferred_Nationality__c).Country_Risk_Level__c;
                    objLd.MiFID_Nationality_Document__c = mapNametoCountryMapping.get(objLd.Preferred_Nationality__c).Document_Requirement__c;                    
                } 
               // if(objLd.Client_Age__c >70.00)
              //  {
               //     objLd.MiFID_R1_RiskScore__c = 20;
              //  }
              //  else{
                    objLd.MiFID_R1_RiskScore__c = objLd.MiFID_Country_CI__c+objLd.MiFID_Anticiated_Deposit__c
                    +objLd.MiFID_PEP_GBG_Score__c+objLd.MiFID_Delivery_Channel__c+objLd.MiFID_Product_Score__c+objLd.MiFID_Employment_Cat_Net_Worth__c+objLd.MiFID_Nationality_FATF_EEA_Score__c+objLd.MiFID_EmploymentStatus_Score__c;
                    if(mapNametoCountryMapping.containsKey(objLd.Country_of_Residence__c))
                    {
                        objLd.MiFID_R1_RiskScore__c = objLd.MiFID_R1_RiskScore__c + objLd.MiFID_Country_FATF_EEA_Score__c+objLd.MiFID_Country_CI_Score__c  ;
                    }               
              //  }
                if(objLd.MiFID_R3_RiskScore__c >= 0.0 && objLd.MiFID_R3_RiskScore__c <= 7)
                {
                    objLd.MiFID_R3_Risk_Analysis__c = 'LIMITED RISK';
                }
                else{
                    objLd.MiFID_R3_Risk_Analysis__c = 'REGULAR';
                }
                if(objLd.Financial_Understanding__c == False)
                {
                    objLd.Account_Type_Allowed__c = 'Failed';
                    objLd.Account_Type_Automatic__c = False;
                }
                else
                {
                    if(objLd.Country_of_Residence__c != 'UNITED KINGDOM')
                    {
                        if(objLd.MiFID_R3_Risk_Analysis__c == 'FAIL' || objLd.MiFID_R2_Risk_Analysis__c == 'FAIL'  )
                        {
                            objLd.Account_Type_Allowed__c = 'Failed';
                            objLd.Account_Type_Automatic__c = False;
                        }
                        else if(objLd.MiFID_R3_Risk_Analysis__c == 'LIMITED RISK' && objLd.MiFID_R2_Risk_Analysis__c == 'LIMITED RISK')
                        {
                            objLd.Account_Type_Allowed__c = 'Regular';
                            objLd.Account_Type_Automatic__c = False;
                        }
                        else if(objLd.MiFID_R3_Risk_Analysis__c == 'LIMITED RISK' && objLd.MiFID_R2_Risk_Analysis__c == 'PASS')
                        {
                            objLd.Account_Type_Allowed__c = 'Regular';
                            objLd.Account_Type_Automatic__c = False;
                        }
                        else if(objLd.MiFID_R3_Risk_Analysis__c == 'REGULAR' && objLd.MiFID_R2_Risk_Analysis__c == 'LIMITED RISK' )
                        {
                            objLd.Account_Type_Allowed__c = 'Regular';
                            objLd.Account_Type_Automatic__c = False;
                        }
                        else if(objLd.MiFID_R3_Risk_Analysis__c == 'REGULAR' && objLd.MiFID_R2_Risk_Analysis__c == 'PASS')
                        {
                            objLd.Account_Type_Allowed__c = 'Regular';
                            objLd.Account_Type_Automatic__c = False;
                        }
                    }
                    
                    if(objLd.Country_of_Residence__c == 'UNITED KINGDOM')
                    {
                        if(objLd.MiFID_R3_Risk_Analysis__c == 'FAIL' || objLd.MiFID_R2_Risk_Analysis__c == 'FAIL'  )
                        {
                            objLd.Account_Type_Allowed__c = 'Failed';
                            objLd.Account_Type_Automatic__c = False;
                        }
                        else if(objLd.MiFID_R3_Risk_Analysis__c == 'LIMITED RISK' && objLd.MiFID_R2_Risk_Analysis__c == 'LIMITED RISK' && objLd.ID_check_Failed__c == False)
                        {
                            objLd.Account_Type_Allowed__c = 'Limited Risk';
                            objLd.Account_Type_Automatic__c = True;
                        }
                        else if(objLd.MiFID_R3_Risk_Analysis__c == 'LIMITED RISK' && objLd.MiFID_R2_Risk_Analysis__c == 'PASS' && objLd.ID_check_Failed__c == False)
                        {
                            objLd.Account_Type_Allowed__c = 'Limited Risk';
                            objLd.Account_Type_Automatic__c = True;
                        }
                        else if(objLd.MiFID_R3_Risk_Analysis__c == 'REGULAR' && objLd.MiFID_R2_Risk_Analysis__c == 'LIMITED RISK' && objLd.ID_check_Failed__c == False)
                        {
                            objLd.Account_Type_Allowed__c = 'Limited Risk';
                            objLd.Account_Type_Automatic__c = True;
                        }
                        else if(objLd.MiFID_R3_Risk_Analysis__c == 'REGULAR' && objLd.MiFID_R2_Risk_Analysis__c == 'PASS' && objLd.ID_check_Failed__c == False)
                        {
                            objLd.Account_Type_Allowed__c = 'Regular';
                            objLd.Account_Type_Automatic__c = True;
                        }
                        else if(objLd.MiFID_R3_Risk_Analysis__c == 'LIMITED RISK' && objLd.MiFID_R2_Risk_Analysis__c == 'LIMITED RISK' && objLd.ID_check_Failed__c == True)
                        {
                            objLd.Account_Type_Allowed__c = 'Limited Risk';
                            objLd.Account_Type_Automatic__c = False;
                        }
                        else if(objLd.MiFID_R3_Risk_Analysis__c == 'LIMITED RISK' && objLd.MiFID_R2_Risk_Analysis__c == 'PASS' && objLd.ID_check_Failed__c == True)
                        {
                            objLd.Account_Type_Allowed__c = 'Limited Risk';
                            objLd.Account_Type_Automatic__c = False;
                        }
                        else if(objLd.MiFID_R3_Risk_Analysis__c == 'REGULAR' && objLd.MiFID_R2_Risk_Analysis__c == 'LIMITED RISK' && objLd.ID_check_Failed__c == True)
                        {
                            objLd.Account_Type_Allowed__c = 'Limited Risk';
                            objLd.Account_Type_Automatic__c = False;
                        }
                        else if(objLd.MiFID_R3_Risk_Analysis__c == 'REGULAR' && objLd.MiFID_R2_Risk_Analysis__c == 'PASS' && objLd.ID_check_Failed__c == True)
                        {
                            objLd.Account_Type_Allowed__c = 'Regular';
                            objLd.Account_Type_Automatic__c = False;
                        }
                    }
                }   
            }       
        }
    }
    
     /* Author : Ashish Pandey 
       Description : Checks the History tracking of the fields on Lead, any modification on fields defined in custom label, gets tracked in History Tracking object.   */
    public static void createHistoryTracking()
    {
        Map<id,Lead> leadOldMap = (Map<id,Lead>)Trigger.oldMap;
        Map<id,Lead> leadNewMap = (Map<id,Lead>)Trigger.newMap;
        List<History_Tracking__c> lstHistoryTracking = new list<History_Tracking__c>();     
        String FinalTrackingList = system.Label.LeadFieldsToBeTracked + ',' + system.Label.LeadFieldsToBeTracked1;          
        List<String> finalLstLeadTrack = FinalTrackingList.split(',');      
        for(Lead ld : leadNewMap.values())
        {
            for(String str : finalLstLeadTrack)
            {
                if(ld.get(str) != leadOldMap.get(ld.id).get(str))
                {
                    History_Tracking__c objHT = new History_Tracking__c(Prior_Value__c = string.valueOf(leadOldMap.get(ld.id).get(str)),Current_Value__c = string.valueOf(ld.get(str)),
                    Lead__c = ld.id,Changed_By__c = UserInfo.getUserId(),Changed_Date_Time__c = system.now(),Field_Name__c = str);
                    lstHistoryTracking.add(objHT);
                }
            }
        }
        if(lstHistoryTracking != null && lstHistoryTracking.size()>0)
        {
            insert lstHistoryTracking;
        }
    }  
    
     /* Author : Ashish Pandey 
       Description : Encrypts the record ID for the Lead, on afterInsertDML.   */
       
    public void recordEncryption_onInsert()
    {
        Set<Id> setKenticoLeads = new Set<Id>();
        for(Lead objLd : (List<Lead>)Trigger.new){
            if(System.isFuture()){
                return;
            }
            else{
                if(objLd.Is_Duplicate__c == false)
                    EncryptRecordId_onInsert.encryptRecordID(objLd.id);
                    system.debug('----> ownerID -> '+objLd.OwnerID);
            }
            
            if(String.valueOf(objLd.OwnerId).startswith('005') && System.Label.ADSSKenticoUserID.contains(objLd.OwnerID) )
            {
                if(objLd.Is_Duplicate__c == False)
                {
                    setKenticoLeads.add(objLd.id);
                }
            }
        } 
        EncryptRecordId_onInsert.Lead_Auto_Reassign(setKenticoLeads);
    }
}