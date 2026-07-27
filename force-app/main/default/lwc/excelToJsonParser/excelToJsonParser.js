import { LightningElement, api } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import sheetjs from '@salesforce/resourceUrl/sheetJS';

export default class ExcelToJsonParser extends LightningElement {
    @api combined = false;
    @api sheets = [];
    @api title = 'Upload a sheet';
    @api message = 'Upload an Excel with .xls or .xlsx extension';

    libraryLoaded = false;

    connectedCallback() {
        loadScript(this, sheetjs).then(() => {
            this.libraryLoaded = true;
        });
    }

    handleFilesChange(event) {
        const files = event.target.files;
        if (files?.[0]) {
            this.excelToJSON(files[0]);
        }
    }

    excelToJSON(file) {
        const reader = new FileReader();

        reader.onload = (loadEvent) => {
            const data = loadEvent.target.result;
            const readOpts = { type: 'binary' };
            if (this.sheets.length > 0) {
                readOpts.sheets = this.sheets;
            }
            const workbook = XLSX.read(data, readOpts);
            const opts = {};
            if (this.combined) {
                opts.header = 1;
            }
            const allSheetsData = workbook.SheetNames.map((name) => ({
                name,
                data: XLSX.utils.sheet_to_json(workbook.Sheets[name], opts)
            }));

            this.dispatchEvent(
                new CustomEvent('parse', {
                    detail: { data: allSheetsData }
                })
            );
        };

        reader.onerror = (ex) => {
            this.dispatchEvent(
                new CustomEvent('parseerror', {
                    detail: { message: ex?.message || 'Failed to read the Excel file.' }
                })
            );
        };

        reader.readAsArrayBuffer(file);
    }
}