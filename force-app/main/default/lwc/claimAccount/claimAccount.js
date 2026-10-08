import { LightningElement, api } from 'lwc';
import claimAccount from '@salesforce/apex/AccountClaimController.claimAccount';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

export default class ClaimAccount extends LightningElement {
    @api recordId;

    @api async invoke() {
        try {
            await claimAccount({ accountId: this.recordId });

            // Refresh standard record page cache
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);

            this.showToast(
                'Success',
                'Account has been successfully claimed.',
                'success'
            );
        } catch (error) {
            this.showToast(
                'Error',
                error?.body?.message || 'An error occurred while claiming the account.',
                'error'
            );
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}