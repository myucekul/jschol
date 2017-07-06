// ##### NotYetLink Component (temporary modal for for functionality/pages that are "Coming Soon") ##### //

import React from 'react'
import ModalComp from '../components/ModalComp.jsx'

class ModalNotYetComp extends React.Component {
  content = (<div>You've reached a portion of our beta site that isn't quite ready,<br/>but will be included in the final release.<br/>For more information, or to provide feedback, visit the <a href="http://help.escholarship.org/support/discussions/forums/9000203294" target="_blank">Help Center</a>.</div>)
  render () {
    return (
      <ModalComp isOpen={this.props.isOpen}
         header="Coming Soon"
         content={this.content}
         onOK={this.props.onOK} okLabel="OK" />
    )
  }
}

class NotYetLink extends React.Component {
  state = { modalOpen: false }

  closeModal = e => {
    this.setState({modalOpen:false})
  }

  clickHandler = event =>{
    this.setState({modalOpen:true})
    event.preventDefault()
  }


  render() {
    let element = this.props.element
    return (
     element == "button" ?
       <button key="1" className={this.props.className} onClick={(e)=>this.clickHandler(e)}>
         {this.props.children}
         <ModalNotYetComp isOpen={this.state.modalOpen} onOK={e=>this.closeModal(e)}/>
       </button>
     :
       <a href="" className={this.props.className} onClick={(e)=>this.clickHandler(e)}>
         {this.props.children}
         <ModalNotYetComp isOpen={this.state.modalOpen} onOK={e=>this.closeModal(e)}/>
       </a>
    )
  }
}

module.exports = NotYetLink;
