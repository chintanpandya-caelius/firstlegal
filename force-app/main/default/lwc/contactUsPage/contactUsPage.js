import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation'; 
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import Id from '@salesforce/user/Id';
import IS_FCP_CUSTOMER_FIELD from '@salesforce/schema/User.Contact.Account.Is_FCP_Customer__c';

export default class ContactUsPage extends NavigationMixin(LightningElement){

    userId = Id;

    @wire(getRecord, { recordId: '$userId', fields: [IS_FCP_CUSTOMER_FIELD] })
    userData;

    //Will come from the Account
    fcpTeamName = 'Harbor Law LLP';
    fcpPhone = '(800) 555-0142';
    fcpEmail = 'harborlaw@firstlegal.com';

    generalPhone = '(800) 889-0111';
    generalEmail = 'clientcare@firstlegal.com';

    _fcpEmailHref = `mailto:${this.fcpEmail}`;
    _generalEmailHref = `mailto:${this.generalEmail}`;
    _fcpDescription = `As a First Class Program account (${this.fcpTeamName}), you have a dedicated team and a direct line.`;

    get fcpEmailHref() {
        return this._fcpEmailHref;
    }

    get generalEmailHref() {
        return this._generalEmailHref;
    }

    get fcpDescription() {
        return this._fcpDescription;
    }

    get isFcpCustomer() {
    const flag = getFieldValue(this.userData.data, IS_FCP_CUSTOMER_FIELD);
    if(flag){
        return flag
    }
    else{
        return false
    }
    }

    handleSubmitTicket() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'TicketSubmission__c'
            }
        });
    }
}