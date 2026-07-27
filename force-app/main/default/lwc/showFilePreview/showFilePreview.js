import { LightningElement, api } from 'lwc';
import { loadStyle, loadScript } from "lightning/platformResourceLoader";
import viewerjs from "@salesforce/resourceUrl/viewerjs";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

export default class ShowFilePreview extends LightningElement {
  @api imageValue;
  @api imageList = [];
  @api inline = false;
  showPdfImages = true;
  gallery;
  attempts = 0;

viewerInstance;
  connectedCallback() {

    Promise.all([loadScript(this, viewerjs + "/viewerjs/viewer.js"), loadStyle(this, viewerjs + "/viewerjs/viewer.css")])
      .then(() => {
        this.showPreviewImage();
        //    alert('script loaded')
      })
      .catch((error) => {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Error loading D3",
            message: error.message,
            variant: "error",
          }),
        );
      });
  }

  @api
  closeFromChild() {
    this.gallery.hidden();
  }

  disconnectedCallback() {
    this.destroyViewer();
  }

  destroyViewer() {
    if (this.viewerInstance) {
      this.viewerInstance.destroy(); // [1]
      this.viewerInstance = null;
    }
  }


  showPreviewImage() {

    if (this.imageList.length) {
      const ImageViewer = window.Viewer;
      this.showPdfImages = true;
      this.template.querySelector('.img-list').addEventListener('shown', () => {

        window.document.querySelectorAll('[id ^= "viewer"]').forEach(element => {
          element.style = 'z-index:9001;'
        });
      })
      this.template.querySelector('.img-list').addEventListener('hidden', () => {
        const selectedClose = true;
        const selectedEvent = new CustomEvent("closepreview", {
          detail: selectedClose
        });

        // Dispatches the event.
        this.dispatchEvent(selectedEvent);
        console.log('testing', window.document.getElementById('viewer0').style = '')
      })

      this.gallery = new ImageViewer(this.template.querySelector('.img-list')

        , {
          inline: this.inline,
          minHeight: 700,
          navbar: true,
          className: 'viewer-container1',
          toolbar: {
            zoomIn: { show: true, size: 'large' },
            zoomOut: { show: true, size: 'large' },
            next: { show: true, size: 'large' },
            play: {
              show: false

            },
            rotateLeft: { show: true, size: 'large' },
            rotateRight: { show: true, size: 'large' },
            flipHorizontal: { show: false, size: 'large' },
            flipVertical: { show: false, size: 'large' },
            oneToOne: { show: false, size: 'large' },
            prev: { show: true, size: 'large' },
            //  play:{show:true},
          }
        }
      );

      this.gallery.show();
      // console.log(this.template.querySelector('.viewer-container'))
      // this.template.querySelector('div.viewer-canvas > img')
    } else {
      this.showPdfImages = false;
      // Use setTimeout to wait for the DOM to update after setting showPdfImages = false
      setTimeout(() => {
        const img = this.template.querySelector('.activeImg');
        if (img) {
          const ImageViewer = window.Viewer;
          this.viewerInstance = new ImageViewer(img, {
            inline: this.inline,
            minHeight: 700,
            navbar: false,
            toolbar: {
              zoomIn: { show: true, size: 'large' },
              zoomOut: { show: true, size: 'large' },
              rotateLeft: { show: true, size: 'large' },
              rotateRight: { show: true, size: 'large' },
            },
            // 2. Bind the close event here
            hidden: () => {
              this.handleViewerClose();
            }
          });
          this.viewerInstance.show();
        }
      }, 0);
    }

  }

  handleViewerClose() {
        // Notify parent to close the modal
        const closeEvent = new CustomEvent("closepreview", {
            detail: true
        });
        this.dispatchEvent(closeEvent);
        
        // Ensure the viewer is fully destroyed
        this.destroyViewer();
    }


  handleClose() {
    if (this.imageList.length) {
      this.showPdfImages = false;
      this.imageList = [];
    } else {
      this.showPdfImages = true;
    }
    const selectedClose = true;
    const selectedEvent = new CustomEvent("closepreview", {
      detail: selectedClose
    });

    // Dispatches the event.
    this.dispatchEvent(selectedEvent);
  }


  contextError(event) {
    event.preventDefault();
  }

  imageError(event) {
    event.target.style.display = 'none';
  }

  handleImageSuccess(event) {
    console.log('finally success');
    if(this.gallery) {
      this.gallery.hidden();
      this.showPreviewImage();
    }
  }

  handleImageError(event) {
    console.log('going in again');
    const imgElement = event.target;
    setTimeout(() => {
      imgElement.src = this.imageValue + '&t=' + new Date().getTime();
    }, 1000);
  }
}