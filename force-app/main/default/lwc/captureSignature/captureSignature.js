import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import FORM_FACTOR from '@salesforce/client/formFactor';

const STROKE_COLOR = '#0000FF'
const STROKE_WIDTH = 1.5

let isDownFlag = false
let isDotFlag = false
let prevX = 0
let currX = 0
let prevY = 0
let currY = 0
let canvasElement
let ctx

export default class CaptureSignature extends LightningElement {
  @api documentid

  hasDrawn = false

  constructor() {
    super()
    this.template.addEventListener('mousemove', this.handleMouseMove.bind(this))
    this.template.addEventListener('mousedown', this.handleMouseDown.bind(this))
    this.template.addEventListener('mouseup', this.handleMouseUp.bind(this))
    this.template.addEventListener('mouseout', this.handleMouseOut.bind(this))
    this.template.addEventListener('touchstart', this.handleTouchDown.bind(this))
    this.template.addEventListener('touchmove', this.handleTouchMove.bind(this))
    this.template.addEventListener('touchend', this.handleTouchUp.bind(this))
  }

  renderedCallback() {
    canvasElement = this.template.querySelector('canvas')
    if (canvasElement) {
      ctx = canvasElement.getContext('2d')
    }
  }

  handleMouseMove(event) {
    this.searchCoordinatesForEvent('move', event)
  }

  handleMouseDown(event) {
    this.searchCoordinatesForEvent('down', event)
  }

  handleMouseUp(event) {
    this.searchCoordinatesForEvent('up', event)
  }

  handleMouseOut(event) {
    this.searchCoordinatesForEvent('out', event)
  }

  handleTouchMove(event) {
    event.preventDefault()
    this.searchCoordinatesForEvent('move', event)
  }

  handleTouchDown(event) {
    event.preventDefault()
    this.searchCoordinatesForEvent('down', event)
  }

  handleTouchUp(event) {
    event.preventDefault()
    this.searchCoordinatesForEvent('up', event)
  }

  @api
  handleSaveClick() {
    if (!this.hasDrawn) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Error',
          message: 'Draw your signature before saving.',
          variant: 'error'
        })
      )
      return
    }

    if (!canvasElement || !ctx || !this.documentid) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Error',
          message: 'Signature capture is not ready.',
          variant: 'error'
        })
      )
      return
    }

    ctx.globalCompositeOperation = 'destination-over'
    ctx.fillStyle = '#FFF'
    ctx.fillRect(0, 0, canvasElement.width, canvasElement.height)

    const dataUrl = canvasElement.toDataURL('image/png')
    const base64Data = dataUrl.replace(/^data:image\/(png|jpg);base64,/, '')

    this.dispatchEvent(
      new CustomEvent('signaturecapture', {
        detail: {
          documentId: this.documentid,
          base64Data,
          fileName: 'Signature.png'
        }
      })
    )
  }

  @api
  handleClearClick() {
    if (canvasElement && ctx) {
      ctx.clearRect(0, 0, canvasElement.width, canvasElement.height)
    }
    this.hasDrawn = false
  }

  searchCoordinatesForEvent(requestedEvent, event) {
    event.preventDefault()

    if (requestedEvent === 'down') {
      this.setupCoordinate(event)
      isDownFlag = true
      isDotFlag = true
      if (isDotFlag) {
        this.drawDot()
        isDotFlag = false
      }
    }
    if (requestedEvent === 'up' || requestedEvent === 'out') {
      isDownFlag = false
    }
    if (requestedEvent === 'move' && isDownFlag) {
      this.setupCoordinate(event)
      this.redraw()
    }
  }

  setupCoordinate(eventParam) {
    const clientRect = canvasElement.getBoundingClientRect()
    prevX = currX
    prevY = currY

    if (FORM_FACTOR === 'Large') {
      currX = eventParam.clientX - clientRect.left
      currY = eventParam.clientY - clientRect.top
    } else {
      const touch = eventParam.touches[0]
      currX = touch.pageX - clientRect.left
      currY = touch.pageY - clientRect.top
    }
  }

  redraw() {
    this.hasDrawn = true
    ctx.beginPath()
    ctx.moveTo(prevX, prevY)
    ctx.lineTo(currX, currY)
    ctx.strokeStyle = STROKE_COLOR
    ctx.lineWidth = STROKE_WIDTH
    ctx.closePath()
    ctx.stroke()
  }

  drawDot() {
    this.hasDrawn = true
    ctx.beginPath()
    ctx.fillStyle = STROKE_COLOR
    ctx.fillRect(currX, currY, STROKE_WIDTH, STROKE_WIDTH)
    ctx.closePath()
  }
}