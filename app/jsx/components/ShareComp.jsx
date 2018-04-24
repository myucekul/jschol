// ##### Share Component ##### //

import React from 'react'
import $ from 'jquery'
import DropdownMenu from '../components/DropdownMenu.jsx'

class ShareComp extends React.Component {
  getLink = (event, type, id, service) => {
    event.preventDefault()
    $.getJSON("/api/mediaLink/"+type+"/"+id+"/"+service).done((data) => {
      window.location = data.url
    }).fail((jqxhr, textStatus, err)=> {
      console.log("Failed! textStatus=", textStatus, ", err=", err)
    })
  }

  render() {
    let p = this.props
    return (
      <DropdownMenu detailsClass="c-share" summarySpan="Share">
        <div className="c-share__list">
          <a className="c-share__email" href="" onClick={e => {this.getLink(e, p.type, p.id, "email")}}>Email</a>
          <a className="c-share__facebook" href="" onClick={e => {this.getLink(e, p.type, p.id, "facebook")}}>Facebook</a>
          <a className="c-share__twitter" href="" onClick={e => {this.getLink(e, p.type, p.id, "twitter")}}>Twitter</a>
        </div>
      </DropdownMenu>
    )
  }
}

module.exports = ShareComp;
