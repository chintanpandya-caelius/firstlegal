import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation'; 

export default class ContactUsPage extends NavigationMixin(LightningElement){
    //Hardcoding the boolean flags
    //This will be replaced via this logic (Experience User -> Contact -> Personal Account)
    isFirstClassProgram = false;

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

    handleSubmitTicket() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'TicketSubmission__c'
            }
        });
    }
}