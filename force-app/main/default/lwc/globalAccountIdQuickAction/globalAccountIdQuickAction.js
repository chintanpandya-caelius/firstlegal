import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';


import generateGlobalAccountId from '@salesforce/apex/AccountGlobalIdController.generateGlobalAccountId';

export default class GlobalAccountIdQuickAction extends LightningElement {

    @api recordId;

    isProcessing = false;

    handleCancel() {
        console.log('User clicked Cancel.');
        this.closeQuickAction();
    }

    async handleConfirm() {
        console.log('User clicked Yes.');

        this.isProcessing = true;

        try {
            console.log(
                'Calling Apex for Account:',
                this.recordId
            );

            await generateGlobalAccountId({
                accountId: this.recordId
            });

            

            console.log(
                'Global Account ID generation request submitted.'
            );

            this.showToast(
                'Success',
                'Global Account ID generation has been initiated successfully.',
                'success'
            );
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            window.location ='/lightning/r/Account/'+this.recordId+'/view' ;


        } catch (error) {

            console.error(
                'Error generating Global Account ID:',
                error
            );

            this.showToast(
                'Error',
                this.getErrorMessage(error),
                'error'
            );

        } finally {

            this.isProcessing = false;

            // Close the Salesforce Quick Action
            this.closeQuickAction();
        }
    }

    closeQuickAction() {
        console.log('Closing Salesforce Quick Action...');

        this.dispatchEvent(
            new CloseActionScreenEvent()
        );
    }

    getErrorMessage(error) {
        return error?.body?.message ||
            error?.message ||
            'An unexpected error occurred.';
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