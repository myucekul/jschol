// ##### Item Page ##### //

import React from 'react'

import PageBase from './PageBase.jsx'
import Header2Comp from '../components/Header2Comp.jsx'
import Subheader2Comp from '../components/Subheader2Comp.jsx'
import NavBarComp from '../components/NavBarComp.jsx'
import BreadcrumbComp from '../components/BreadcrumbComp.jsx'
import TabsComp from '../components/TabsComp.jsx'
import JumpComp from '../components/JumpComp.jsx'
import FooterComp from '../components/FooterComp.jsx'

const anchors = ['main', 'supplemental', 'metrics', 'author',
             'article_abstract', 'article_main', 'article_references']

class ItemPage extends PageBase {
  static propTypes = {
    currentTab: React.PropTypes.oneOf(anchors)
  }

  state = { currentTab: "main" }

  // PageBase will fetch the following URL for us, and place the results in this.state.pageData
  pageDataURL() {
    return "/api/item/" + this.props.params.itemID
  }

  componentDidUpdate() {
    var h = location.hash.toLowerCase().replace(/^#/, "")
    h = (h.startsWith("article") ? "main" : h)
    if ((h != this.state.currentTab) && anchors.includes(h)) {
      this.setState({currentTab: h}) 
    }
  }

  changeTab = tabName => {
    this.setState({currentTab: tabName})
    window.location.hash=tabName
  }

  renderData = data => {
    return (
      <div>
        <Header2Comp type={data.unit ? data.unit.type: null}
                     unitID={data.appearsIn.length > 0 ? data.appearsIn[0]["id"] : null } />
        {data.header && <Subheader2Comp unit={data.unit}
                                        campusID={data.header.campusID}
                                        campusName={data.header.campusName}
                                        campuses={data.header.campuses} />}
        {data.header && <NavBarComp navBar={data.header.nav_bar} 
                                    unit={data.unit} 
                                    socialProps={data.header.social} />}
        <BreadcrumbComp array={data.header ? data.header.breadcrumb : null} />
        <div className="c-columns--sticky-sidebar">
          <main id="maincontent">
            <TabsComp currentTab={this.state.currentTab}
                      {...data} />
          </main>
          <aside>
            {(data.status == "published" && data.content_type) &&
              <section className="o-columnbox1">
                <header>
                  <h2>Jump To</h2>
                </header>
                <JumpComp changeTab={this.changeTab} attrs={data.attrs} />
              </section>
            }
            <section className="o-columnbox1">
              <header>
                <h2>Related Items</h2>
              </header>
              <p><a className="o-textlink__secondary" href="">Collaborative Film Authorship: Writing Latinas Into the Picture</a><br/>CSW update</p>
              <p><a className="o-textlink__secondary" href="">Sporting Bodies, Displaying History: Black Embodiment</a><br/>UCLA Electronic Theses and Dissertations</p>
              <p><a className="o-textlink__secondary" href="">United States-Based Latina Producers of Feature Films</a><br/>UCLA Electronic Theses and Dissertations</p>
            </section>
          </aside>
        </div>
      </div>
    )
  }
}

module.exports = ItemPage;
