// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import UIKit
import Shared
import Storage
import SiteImageView

private struct RecentlyClosedPanelUX {
    static let IconSize = CGSize(width: 23, height: 23)
    static let IconBorderColor = UIColor.Photon.Grey30
    static let IconBorderWidth: CGFloat = 0.5
}

protocol RecentlyClosedPanelDelegate: AnyObject {
    func openRecentlyClosedSiteInSameTab(_ url: URL)
    func openRecentlyClosedSiteInNewTab(_ url: URL, isPrivate: Bool)
}

class RecentlyClosedTabsPanel: UIViewController, LibraryPanel {
    weak var libraryPanelDelegate: LibraryPanelDelegate?
    var state: LibraryPanelMainState = .history(state: .inFolder)
    var recentlyClosedTabsDelegate: RecentlyClosedPanelDelegate?
    let profile: Profile
    var bottomToolbarItems: [UIBarButtonItem] = [UIBarButtonItem]()

    fileprivate lazy var tableViewController = RecentlyClosedTabsPanelSiteTableViewController(profile: profile)

    init(profile: Profile) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.legacyTheme.tableView.headerBackground

        tableViewController.libraryPanelDelegate = libraryPanelDelegate
        tableViewController.recentlyClosedTabsDelegate = recentlyClosedTabsDelegate
        tableViewController.recentlyClosedTabsPanel = self

        self.addChild(tableViewController)
        tableViewController.didMove(toParent: self)

        self.view.addSubview(tableViewController.view)

        NSLayoutConstraint.activate([
            tableViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            tableViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        /// BVC is assigned as `RecentlyClosedTabsPanel` delegate, to support opening tabs from within it.
        /// Previously, BVC was assigned it on panel creation via a foregroundBVC call. But it can be done this way, to
        /// avoid that call. `sceneForVC` will use the focused, active and foregrounded scene's BVC.
        guard recentlyClosedTabsDelegate != nil else {
            recentlyClosedTabsDelegate = sceneForVC?.browserViewController

            return
        }
    }
}

class RecentlyClosedTabsPanelSiteTableViewController: SiteTableViewController {
    weak var libraryPanelDelegate: LibraryPanelDelegate?
    var recentlyClosedTabsDelegate: RecentlyClosedPanelDelegate?
    var recentlyClosedTabs: [ClosedTab] = []
    weak var recentlyClosedTabsPanel: RecentlyClosedTabsPanel?

    fileprivate lazy var longPressRecognizer: UILongPressGestureRecognizer = {
        return UILongPressGestureRecognizer(target: self, action: #selector(RecentlyClosedTabsPanelSiteTableViewController.longPress))
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.addGestureRecognizer(longPressRecognizer)
        tableView.accessibilityIdentifier = "Recently Closed Tabs List"
        self.recentlyClosedTabs = profile.recentlyClosedTabs.tabs
    }

    @objc fileprivate func longPress(_ longPressGestureRecognizer: UILongPressGestureRecognizer) {
        guard longPressGestureRecognizer.state == .began else { return }
        let touchPoint = longPressGestureRecognizer.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: touchPoint) else { return }
        presentContextMenu(for: indexPath)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        guard let twoLineCell = cell as? TwoLineImageOverlayCell else {
            return cell
        }
        let tab = recentlyClosedTabs[indexPath.row]
        let displayURL = tab.url.displayURL ?? tab.url
        twoLineCell.descriptionLabel.isHidden = false
        twoLineCell.titleLabel.text = tab.title
        twoLineCell.titleLabel.isHidden = tab.title?.isEmpty ?? true ? true : false
        twoLineCell.descriptionLabel.text = displayURL.absoluteDisplayString
        twoLineCell.leftImageView.layer.borderColor = RecentlyClosedPanelUX.IconBorderColor.cgColor
        twoLineCell.leftImageView.layer.borderWidth = RecentlyClosedPanelUX.IconBorderWidth
        twoLineCell.leftImageView.setFavicon(FaviconImageViewModel(siteURLString: displayURL.absoluteString))

        return twoLineCell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        recentlyClosedTabsDelegate?.openRecentlyClosedSiteInNewTab(recentlyClosedTabs[indexPath.row].url, isPrivate: false)
        let visitType = VisitType.typed    // Means History, too.
        libraryPanelDelegate?.libraryPanel(didSelectURL: recentlyClosedTabs[indexPath.row].url, visitType: visitType)
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }

    // Functions that deal with showing header rows.
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.recentlyClosedTabs.count
    }

    // MARK: - Libray Toolbar actions
    func handleBackButton() {
        // no implementation needed
    }

    func handleDoneButton() {
        // no implementation needed
    }
}

extension RecentlyClosedTabsPanelSiteTableViewController: LibraryPanelContextMenu {
    func presentContextMenu(for site: Site, with indexPath: IndexPath, completionHandler: @escaping () -> PhotonActionSheet?) {
        guard let contextMenu = completionHandler() else { return }
        self.present(contextMenu, animated: true, completion: nil)
    }

    func getSiteDetails(for indexPath: IndexPath) -> Site? {
        let closedTab = recentlyClosedTabs[indexPath.row]
        let site: Site
        if let title = closedTab.title {
            site = Site(url: String(describing: closedTab.url), title: title)
        } else {
            site = Site(url: String(describing: closedTab.url), title: "")
        }
        return site
    }

    func getContextMenuActions(for site: Site, with indexPath: IndexPath) -> [PhotonRowActions]? {
        guard let libraryPanelDelegate = libraryPanelDelegate else {
            return getRecentlyClosedTabContexMenuActions(for: site, recentlyClosedPanelDelegate: recentlyClosedTabsDelegate)
        }
        return getDefaultContextMenuActions(for: site, libraryPanelDelegate: libraryPanelDelegate)
    }
}

extension RecentlyClosedTabsPanel: NotificationThemeable {
    func applyTheme() {
        tableViewController.tableView.reloadData()
    }
}
