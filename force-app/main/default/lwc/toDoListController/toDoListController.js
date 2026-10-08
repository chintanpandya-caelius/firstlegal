import { LightningElement, wire, track } from 'lwc';
import getActivityCenterData from '@salesforce/apex/TodolistController.getActivityCenterData';
import completeTask from '@salesforce/apex/TodolistController.completeTask';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const TODAY_COLUMNS = [
    {
        label: 'Subject',
        fieldName: 'recordLink',
        type: 'url',
        typeAttributes: { label: { fieldName: 'subject' }, target: '_blank' },
        wrapText: true
    },
    { label: 'Details', fieldName: 'details', type: 'text', wrapText: true },
    {
        type: 'button-icon',
        initialWidth: 40,
        typeAttributes: {
            iconName: 'utility:check',
            name: 'complete_activity',
            title: 'Complete',
            variant: 'border-filled',
            disabled: { fieldName: 'isNotCompletable' }
        }
    }
];

const OVERDUE_COLUMNS = [
    {
        label: 'Subject',
        fieldName: 'recordLink',
        type: 'url',
        typeAttributes: { label: { fieldName: 'subject' }, target: '_blank' },
        wrapText: true
    },
    { label: 'Details', fieldName: 'details', type: 'text', wrapText: true },
    { label: 'Due', fieldName: 'dueDate', type: 'date-local', initialWidth: 90 },
    {
        type: 'button-icon',
        initialWidth: 40,
        typeAttributes: {
            iconName: 'utility:check',
            name: 'complete_activity',
            title: 'Complete',
            variant: 'border-filled'
        }
    }
];

export default class Todoistcontroller extends LightningElement {
    @track todayActivities = [];
    @track overdueActivities = [];
    
    todayColumns = TODAY_COLUMNS;
    overdueColumns = OVERDUE_COLUMNS;
    wiredResult;

    @track isModalOpen = false;
    @track modalTitle = '';
    @track modalData = [];
    @track modalColumns = [];

    @wire(getActivityCenterData)
    wiredActivities(result) {
        this.wiredResult = result;
        if (result.data) {
            this.todayActivities = result.data.todayActivities.map(item => ({
                ...item,
                isNotCompletable: !item.isCompletable
            }));
            this.overdueActivities = result.data.overdueActivities;
        } else if (result.error) {
            console.error('Error loading tasks:', result.error);
        }
    }

    get previewTodayActivities() {
        return this.todayActivities.slice(0, 5);
    }

    get previewOverdueActivities() {
        return this.overdueActivities.slice(0, 5);
    }

    get todayCount() {
        return this.todayActivities ? this.todayActivities.length : 0;
    }

    get overdueCount() {
        return this.overdueActivities ? this.overdueActivities.length : 0;
    }

    get hasTodayActivities() {
        return this.todayCount > 0;
    }

    get hasOverdueActivities() {
        return this.overdueCount > 0;
    }

    openTodayModal() {
        this.modalTitle = "Today's Tasks & Activities";
        this.modalData = this.todayActivities;
        this.modalColumns = TODAY_COLUMNS;
        this.isModalOpen = true;
    }

    openOverdueModal() {
        this.modalTitle = "Overdue Tasks & Reminders";
        this.modalData = this.overdueActivities;
        this.modalColumns = OVERDUE_COLUMNS;
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
    }

    async handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'complete_activity') {
            try {
                await completeTask({ taskId: row.recordId });
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Task completed',
                        variant: 'success'
                    })
                );
                await refreshApex(this.wiredResult);
            } catch (error) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Unable to update task',
                        variant: 'error'
                    })
                );
            }
        }
    }
}