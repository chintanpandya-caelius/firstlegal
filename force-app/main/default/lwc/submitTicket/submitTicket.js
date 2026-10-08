import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import CASE_OBJECT from '@salesforce/schema/Case';
import TYPE_FIELD from '@salesforce/schema/Case.Type';
import SUBTYPE_FIELD from '@salesforce/schema/Case.Ticket_SubType__c';
import PRIORITY_FIELD from '@salesforce/schema/Case.Priority';
import TICKET_CREATED from '@salesforce/label/c.Ticket_Creation_via_LWC'
import getCurrentUserEmail from '@salesforce/apex/TicketController.getCurrentUserEmail';
import submitTicket from '@salesforce/apex/TicketController.submitTicket';
import getRecordTypeId from '@salesforce/apex/TicketController.getRecordTypeId';

const METADATA_LOAD_FAILED = 'Could not load ticket metadata';
const PICKLIST_VALUE_RETRIEVAL_FAILED = 'Could not load one or more of Type, Sub-Type or Priority picklist values';
const LOADING = 'Loading...';
const MISSING_REQUIRED_FIELDS = 'Please fill in all required fields.';
const UNKNOWN_ERROR = 'An unknown error occurred. Please try again.';

function replaceTicketNumberInLabel(label, ticketNumber) {
    if (!label) {
        return '';
    }
    return label.replace(/\$\{ticketNumber\}/g, ticketNumber)
}

export default class SubmitTicket extends NavigationMixin(LightningElement) {
    recordTypeId;
    subtypeMeta;
    userEmail = '';
    ticketType = '';
    subType = '';
    priority = '';
    subject = '';
    description = '';
    matterNumber = '';
    courtCaseNumber = '';
    successMessage = '';
    contentDocumentIds = [];
    typeOptions = [];
    priorityOptions = [];
    uploadedFileNames = [];
    isPicklistLoading = true;
    isSubmitting = false;
    showSuccessBanner = false;
    acceptedFormats = ['.pdf', '.docx', '.png', '.jpg', '.jpeg'];

    @wire(getRecordTypeId)
    wiredRecordTypeId({ data, error }){
        if(data){
            this.recordTypeId = data;
            console.log(this.recordTypeId);
        }else if(error){
            console.error(METADATA_LOAD_FAILED, error);
        }
    }

    @wire(getPicklistValuesByRecordType, {objectApiName: CASE_OBJECT, recordTypeId: '$recordTypeId'})
    wiredPicklistValues({ data, error }) {
        if (data) {
            const typeField = data.picklistFieldValues[TYPE_FIELD.fieldApiName];
            const subtypeField = data.picklistFieldValues[SUBTYPE_FIELD.fieldApiName];
            const priorityField = data.picklistFieldValues[PRIORITY_FIELD.fieldApiName];

            this.priorityOptions = priorityField 
                ? priorityField.values.map((v) => ({label: v.label, value: v.value}))
                : [];

            this.typeOptions = typeField
                ? typeField.values.map((v) => ({ label: v.label, value: v.value }))
                : [];
            this.subtypeMeta = subtypeField;
            this.isPicklistLoading = false;
        } else if (error) {
       
            console.error(PICKLIST_VALUE_RETRIEVAL_FAILED, error);
            this.isPicklistLoading = false;
        }
    }

    //Dependent Picklist
    get subTypeOptions() {
        if (!this.ticketType || !this.subtypeMeta) {
            return [];
        }
        const controllingIndex = this.subtypeMeta.controllerValues[this.ticketType];
        if (controllingIndex === undefined) {
            return [];
        }
        return this.subtypeMeta.values
            .filter((entry) => entry.validFor.includes(controllingIndex))
            .map((entry) => ({ label: entry.label, value: entry.value }));
    }

    get isSubTypeDisabled() {
        return !this.ticketType || this.isPicklistLoading;
    }

    get subTypePlaceholder() {
        if (this.isPicklistLoading) {
            return LOADING;
        }
        return this.ticketType ? '--None--' : 'Select a Ticket Type first';
    }

    get isUploadDisabled(){
        return !(this.subject && this.description && this.priority && this.ticketType && this.subType);
    }

    connectedCallback() {
        getCurrentUserEmail()
            .then((email) => {
                this.userEmail = email;
            })
            .catch(() => {
                this.userEmail = '';
            });
    }

    handleTicketTypeChange(event) {
        this.ticketType = event.detail.value;
        this.subType = '';
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.detail.value;
    }

    handleUploadFinished(event) {
            const uploadedFiles = event.detail.files || [];

            this.contentDocumentIds = [
                ...this.contentDocumentIds,
                ...uploadedFiles.map((file) => file.documentId)
            ];

            this.uploadedFileNames = [
                ...this.uploadedFileNames,
                ...uploadedFiles.map((file) => file.name)
            ];
    }

    //This implementation is pending discussion
    //cc: Ekta Ma'am
    validateFields() {
        const requiredEls = this.template.querySelectorAll(
            'lightning-input[required], lightning-combobox[required], lightning-textarea[required]'
        );
        let allValid = true;
        requiredEls.forEach((el) => {
            if (!el.reportValidity()) {
                allValid = false;
            }
        });
        return allValid;
    }

    handleSubmit() {
        if (!this.validateFields()) {
            this.showToast('Error', MISSING_REQUIRED_FIELDS, 'error');
            return;
        }

        this.isSubmitting = true;
        this.showSuccessBanner = false;

        console.log("Inside handle submit and just before calling submitTicket apex")

        submitTicket({
            contactEmail: this.userEmail,
            ticketType: this.ticketType,
            subType: this.subType,
            priority: this.priority,
            subject: this.subject,
            description: this.description,
            matterNumber: this.matterNumber,
            courtCaseNumber: this.courtCaseNumber,
            cDocumentIds : this.contentDocumentIds
        })
            .then((ticket) => {
                console.log("The returned object: ", ticket);
                console.log("Before setting the variables for html");
                this.successMessage = replaceTicketNumberInLabel(TICKET_CREATED, ticket.CaseNumber);
                this.showSuccessBanner = true;
                const message = replaceTicketNumberInLabel(TICKET_CREATED, ticket.CaseNumber);
                console.log("After setting the variables for html");

                console.log("Before showToast event");

                this.showToast(
                    'Ticket submitted',
                    message,
                    'success'
                );

                console.log("After showToast event");

                console.log("Resetting the form");
                this.resetForm();
                console.log("Form reset successful");

                setTimeout(() => {
                    const banner = this.template.querySelector('.slds-scoped-notification');
                    if (banner) {
                        banner.scrollIntoView({ behavior: 'smooth', block: 'start' });
                    }
                }, 0);

                setTimeout(() => {
                    this[NavigationMixin.Navigate]({
                        type: 'standard__recordPage',
                        attributes: {
                            recordId: ticket.Id,
                            objectApiName: 'Case',
                            actionName: 'view'
                        }
                    });
                }, 1500);
            })
            .catch((error) => {
                this.showToast(
                    'Error submitting ticket',
                    this.extractErrorMessage(error),
                    'error'
                );
            })
            .finally(() => {
                this.isSubmitting = false;
            });
    }

    handleDismissBanner() {
        this.showSuccessBanner = false;
    }

    handleCancel() {
        this.resetForm();
        this.dispatchEvent(new CustomEvent('cancel'));
        this[NavigationMixin.Navigate]({
            type       : 'comm__namedPage',
            attributes : {
                name : 'Home'
            }
        });
    }

    resetForm() {
        this.ticketType = '';
        this.subType = '';
        this.priority = '';
        this.subject = '';
        this.description = '';
        this.matterNumber = '';
        this.courtCaseNumber = '';
        this.uploadedFileNames = [];

        this.template
            .querySelectorAll('lightning-input, lightning-textarea, lightning-combobox')
            .forEach((el) => {
                if (typeof el.setCustomValidity === 'function') {
                    el.setCustomValidity('');
                    el.reportValidity();
                }
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractErrorMessage(error) {
        if (error && error.body) {
            if (Array.isArray(error.body)) {
                return error.body.map((e) => e.message).join(', ');
            }
            if (error.body.message) {
                return error.body.message;
            }
        }
        return UNKNOWN_ERROR;
    }
}