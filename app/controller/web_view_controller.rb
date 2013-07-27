# -*- coding: utf-8 -*-
class WebViewController < UIViewController
  attr_accessor :bookmark

  def viewDidLoad
    super

    @link_clicked = nil

    @document_title = nil
    self.navigationItem.backBarButtonItem = UIBarButtonItem.titled("戻る")
    self.view.backgroundColor = '#fff'.uicolor
    self.initialize_toolbar

    ## Title
    self.navigationItem.titleView = TitleLabel.new.tap do |label|
      label.frame = [[0, 0], [view.frame.size.width, 44]]
      label.text = @bookmark.title
    end

    ## WebView
    self.view << @webview = HBFav2::WebView.new.tap do |v|
      v.scalesPageToFit = true
      v.loadRequest(NSURLRequest.requestWithURL(@bookmark.link.nsurl))
      v.delegate = self
    end

    ## Activity Indicator
    self.view << @indicator = UIActivityIndicatorView.new.tap do |v|
      v.style = UIActivityIndicatorViewStyleGray
      v.startAnimating
    end

    ## Readability Button
    self.navigationItem.rightBarButtonItem = UIBarButtonItem.alloc.initWithCustomView(
      UIButton.custom.tap do |btn|
        btn.frame = [[0, 0], [38, 38]]
        btn.showsTouchWhenHighlighted = true
        btn.setImage(UIImage.imageNamed('readability'), forState: :normal.uicontrolstate)
        btn.addTarget(self, action:'open_readability', forControlEvents:UIControlEventTouchUpInside)
      end
    )
  end

  # http://stackoverflow.com/questions/4492683/why-do-i-have-to-subtract-for-height-of-uinavigationbar-twice-to-get-uiwebview-t
  def viewWillAppear(animated)
    super

    ## 応急処置
    UIApplication.sharedApplication.statusBarStyle = UIStatusBarStyleBlackOpaque
    UIApplication.sharedApplication.setStatusBarHidden(false, animated:false)
    self.wantsFullScreenLayout = false

    self.navigationController.setToolbarHidden(false, animated:animated)
    self.navigationController.toolbar.translucent = false

    @webview.frame = view.bounds
    @indicator.center = [view.bounds.size.width / 2, view.bounds.size.height / 2]
  end

  def viewWillDisappear(animated)
    super
    ## これがあると Readability やブコメでローディングが止まっちゃう
    # if @webview.loading?
    #  @webview.stopLoading
    # end

    if @connection.present?
      @connection.cancel
    end
  end

  def webViewDidStartLoad (webView)
    App.shared.networkActivityIndicatorVisible = true
  end

  def webViewDidFinishLoad (webView)
    update_bookmark

    if @backButton.present? and @forwardButton.present?
      @backButton.enabled    = webView.canGoBack
      @forwardButton.enabled = webView.canGoForward
    end
    App.shared.networkActivityIndicatorVisible = false
    @indicator.stopAnimating
  end

  def webView(webView, shouldStartLoadWithRequest:request, navigationType:navigationType)
    if (navigationType == UIWebViewNavigationTypeLinkClicked)
      @link_clicked = true
    end
    true
  end

  def update_bookmark
    url = @webview.request.URL.absoluteString
    query = BW::HTTP.get("http://b.hatena.ne.jp/entry/jsonlite/", {payload: {url: url}}) do |response|
      if response.ok?
        ## まだ画面遷移が一度も発生してない場合はオブジェクトの更新は必要ない (リダイレクト対策)
        ## ただし、その場合でもブックマークコメントの先読みのためにリクエストはしておく
        if @link_clicked
          data = BW::JSON.parse(response.body.to_str) || {}
          @bookmark = Bookmark.new(
            {
              :eid   => data['eid'] || nil,
              :title => data['title'] || @webview.stringByEvaluatingJavaScriptFromString("document.title"),
              :link  => url,
              :count => data['count'] || 0,
              :user => { :name => 'dummy' },
              :datetime => '1977-01-01' # dummy
            }
          )
          ## TODO: もっと複雑になるようなら Observer パターンに変更
          self.navigationItem.titleView.text = @bookmark.title if self.navigationItem.present?
          @bookmarkButton.setTitle(@bookmark.count.to_s, forState:UIControlStateNormal)
          @bookmarkButton.enabled = @bookmark.count.to_i > 0
        end
      else
        # TODO:
      end
      @connection = nil
    end
    @connection = query.connection
  end

  def on_back
    @webview.goBack
  end

  def on_forward
    @webview.goForward
  end

  def on_refresh
    @webview.reload
  end

  def initialize_toolbar
    self.navigationController.setToolbarHidden(false, animated:false)
    self.navigationController.toolbar.translucent = false
    spacer = UIBarButtonItem.flexiblespace

    self.toolbarItems = [
      @backButton = UIBarButtonItem.alloc.initWithBarButtonSystemItem(101, target:self, action:'on_back').tap { |b| b.enabled = false },
      spacer,
      @forwardButton = UIBarButtonItem.alloc.initWithBarButtonSystemItem(102, target:self, action:'on_forward').tap { |b| b.enabled = false },
      spacer,
      UIBarButtonItem.alloc.initWithBarButtonSystemItem(UIBarButtonSystemItemRefresh, target:self, action:'on_refresh'),
      spacer,
      UIBarButtonItem.alloc.initWithBarButtonSystemItem(UIBarButtonSystemItemAction, target:self, action:'on_action'),
      spacer,
      @bookmarkButton = UIBarButtonItem.titled(@bookmark.count.to_s, :bordered).tap do |btn|
        btn.target = self
        btn.action = 'open_bookmark'
      end
    ]
  end

  def open_readability
    controller = ReadabilityViewController.new.tap do |c|
      c.entry = {:title => @bookmark.title, :url => @bookmark.link}
    end
    self.presentViewController(
      UINavigationController.alloc.initWithRootViewController(controller),
      animated:true,
      completion:nil
    )
  end

  def open_bookmark
    controller = BookmarksViewController.new.tap do |c|
      c.entry = @bookmark
    end
    self.presentViewController(
      UINavigationController.alloc.initWithRootViewController(controller),
      animated:true,
      completion:nil
    )
  end

  def on_action
    @safari = TUSafariActivity.new
    @pocket = PocketActivity.new
    @hatena = HatenaBookmarkActivity.new
    @add_bookmark = AddBookmarkActivity.new.tap do |activity|
      user = ApplicationUser.sharedUser
      activity.hatena_id = user.hatena_id
      activity.password  = user.password
    end

    @activity = UIActivityViewController.alloc.initWithActivityItems(
      [@bookmark.title, @bookmark.link.nsurl],
      applicationActivities:[
        @safari,
        @add_bookmark,
        @pocket,
        @hatena,
      ]
    )
    @activity.excludedActivityTypes = [UIActivityTypeMessage, UIActivityTypePostToWeibo]
    self.presentViewController(@activity, animated:true, completion:nil)
  end

  def dealloc
    if @webview.loading?
      @webview.stopLoading
    end
    @webview.delegate = nil
    NSLog("dealloc: " + self.class.name)
    super
  end
end
