import { LightningElement, api,wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import pdflib from "@salesforce/resourceUrl/pdflib";
import { loadScript } from "lightning/platformResourceLoader";

const ONE_MB = 1048576;
const TARGET_IMG_SIZE_FOR_RENDITION = 8;
export default class FilePreview extends NavigationMixin(LightningElement) {
    @api label;
    @api documentId;
    @api variant = 'brand';
    @api disabled;
    @api isCommunity;
    @api fileType;
    @api versionId;
    @api openPreview;
    @api isFromModal;
    @api contentSize;
    @api inline = false;
    @api
    get versionChange() {
        return this.versionChange;
    }
    set versionChange(val){
        this.openPreviewModal = false;
        this.previewFile();
    }


    libraryLoaded = true;

    isPDFFile = false;
    imageList = [];
    imageURL;
    openPreviewModal = false;
    modalLarge;

    isHTMLFile = false;
    @api contentValue;
    currentWidth = 0;
    rotateNumber = 0;
    //
    isVideoFile = false;
    get rotateClass() {
        return 'activeImg rotate' + this.rotateNumber;
    }

    get domLibraryLoaded(){
        return this.libraryLoaded ? true : false;
    }

    lexOrigin;
    connectedCallback() {
        Promise.all([loadScript(this, pdflib)])
        .then(() => {
            this.libraryLoaded = true;
        })
        .catch((error) => {
            console.log(JSON.stringify(error))
        });
        if (this.openPreview) {
            this.previewFile();
        }
        if (this.isFromModal) {
            this.modalLarge = 'slds-modal slds-fade-in-open slds-modal_large';
        } else {
            this.modalLarge = 'slds-modal slds-fade-in-open slds-modal_large';
        }

        let origin = window.location.origin;
        let isSite = location.pathname.split('/').length >=2 && location.pathname.split('/')[2] == 's';
        let lexOrigin;
        if(isSite){
            lexOrigin = origin;
        }else{
            let sandBoxString = origin.includes("sandbox") ? ".sandbox":"";
            lexOrigin = origin.split('.')[0]+'--c'+sandBoxString+".vf.force.com"
        }
        this.lexOrigin = lexOrigin;
    }

    get pageURL(){
        return '/apex/htmlFilePreview';
    }

    previewFile() {
        
        if (this.fileType == 'html' || this.fileType == 'htm') {
            this.openPreviewModal = true;
            this.isHTMLFile = true;
        }
        else {
            this.previewFileForCommunity();
        }
    }

   sendDataToVF(){
        let data ={'source':'FromLightning','value':this.contentValue}
        this.template.querySelector("iframe").contentWindow.postMessage(data, this.lexOrigin);
   }

   loading = false;
   initialLoad = true;
   pageNumber = 5;
   perIteration = 25;
    async previewFileForCommunity() {
        this.closeModal();
        let fileType = this.fileType;
        let urlString = window.location.href;
        let baseURL = urlString.substring(0, urlString.indexOf("/s"));
        let selectedFileUrl = baseURL + '/sfc/servlet.shepherd/version/renditionDownload?';
        if (fileType == 'PDF' || fileType.startsWith('WORD')) {
            selectedFileUrl += 'rendition=SVGZ';
            if (fileType == 'PDF') {
                try {
                    let imageURL = selectedFileUrl + '&versionId=' + this.versionId + '&page=';

                    let promises = [];
                    for (let i = 0; i < this.pageNumber; i++) {
                        promises.push(this.imageExists(imageURL+i));
                    }
                    await Promise.allSettled(promises)
                    .then((results) => {
                        let index = results.findIndex( 
                            (temp) => temp['status'] === 'rejected' 
                        ); 
                        let currentIndex = index > 0 ? index : this.pageNumber;
                        for (let input = 0; input < currentIndex; input++) {
                            this.imageList.push(imageURL+input);
                        }
                        this.isPDFFile = true;
                        if(index < 0){
                            this.resolveAllthePages(imageURL);
                        }
                    })
                    .catch(error => {
                        this.loading = false;
                    });
                } catch (error) {
                    console.error(error)
                }
            }
        } else {
            let defaultRendition = 'THUMB720BY480';
            if(this.contentSize && this.contentSize/ONE_MB > TARGET_IMG_SIZE_FOR_RENDITION){
                defaultRendition = 'ORIGINAL_'+this.fileType[0].toUpperCase()+this.fileType.substring(1).toLowerCase();
            }
            selectedFileUrl += 'rendition='+ defaultRendition + '&versionId=' + this.versionId;
        }
        this.imageURL = selectedFileUrl;
        const closePreviewModal = new CustomEvent("closepreviewmodal", {
            detail: true
        });

        // Dispatches the event.
        this.dispatchEvent(closePreviewModal);
        setTimeout(() => {
            this.openPreviewModal = true;
        }, 0);
    }

    get pdfInitialLoad(){
        return this.isPDFFile && this.initialLoad;
    }

    get pdfNextLoad(){
        return this.isPDFFile && !this.initialLoad;
    }

    closeModal() {
        console.log('close fired')
        this.openPreviewModal = false;
        this.isPDFFile = false;
        this.imageURL = '';
        this.imageList = [];
        const selectedClose = true;
        const selectedEvent = new CustomEvent("progressvaluechange", {
            detail: selectedClose
        });

        this.dispatchEvent(selectedEvent);
        this.isPDFFile = false;
        this.initialLoad = true;
    }

    contextError(event) {
        event.preventDefault();
    }

    imageError(event) {
        event.target.style.display = 'none';
    }

    imageExists = (image_url) => {
        let image = new Image();
        image.src = image_url;
        return new Promise((resolve, reject) => {
            image.onload = () => {
                resolve();
            }
            image.onerror = () => {
                reject();
            }
        });
    };

    async resolveAllthePages(imageURL){
        let promises = [];
        for (let i = this.pageNumber; i < this.pageNumber + this.perIteration; i++) {
            promises.push(this.imageExists(imageURL+i));
        }
        await Promise.allSettled(promises)
        .then((results) => {
            let index = results.findIndex( 
                (temp) => temp['status'] === 'rejected' 
            ); 
            if(index < 0){
                this.pageNumber = this.pageNumber + this.perIteration;
                this.resolveAllthePages(imageURL);
            }else{
                this.imageList = [];
                let currentIndex = index > 0 ? index : this.pageNumber;
                for (let input = 0; input < this.pageNumber + currentIndex; input++) {
                    this.imageList.push(imageURL+input);
                }
                this.openPreviewModal = true;
                this.isPDFFile = true;
                this.initialLoad = false;
            }
        })
        .catch(error => {
            this.loading = false;
        });
    }

    get openModal(){
        return this.openPreviewModal;
    }
}