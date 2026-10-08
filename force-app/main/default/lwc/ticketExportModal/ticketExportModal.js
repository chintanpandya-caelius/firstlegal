import { LightningElement, wire } from 'lwc';
import getExportFieldMetadata from '@salesforce/apex/TicketExportController.getExportFieldMetadata';

export default class TicketExportModal extends LightningElement {
    format = 'CSV';
    fields = [];
    isLoading = true;
    errorMessage;

    @wire(getExportFieldMetadata)
    wiredFields({ data, error }) {
        if (data) {
            this.fields = data.map((f) => ({
                ...f,
                isSelected: f.defaultSelected
            }));
        } else if (error) {
            this.errorMessage =
                (error && error.body && error.body.message) ||
                'Unable to load export fields.';
        }
        this.isLoading = false;
    }

    get isCsv() {
        return this.format === 'CSV';
    }

    handleFormatChange(event) {
        this.format = event.target.value;
    }

    handleFieldToggle(event) {
        const apiName = event.target.dataset.field;
        const checked = event.target.checked;
        this.fields = this.fields.map((f) =>
            f.apiName === apiName ? { ...f, isSelected: checked } : f
        );
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleExportClick() {
        const selectedFields = this.fields.filter((f) => f.isSelected);
        if (selectedFields.length === 0) {
            this.errorMessage = 'Select at least one field to export.';
            return;
        }
        this.errorMessage = undefined;
        this.dispatchEvent(
            new CustomEvent('export', {
                detail: {
                    format: this.format,
                    fields: selectedFields.map((f) => ({
                        apiName: f.apiName,
                        label: f.label
                    }))
                }
            })
        );
    }
}