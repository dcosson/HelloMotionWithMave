class AppDelegate
  def application(application, didFinishLaunchingWithOptions:launchOptions)
    # setup mave sdk (with a fake Application ID)
    MaveSDK.setupSharedInstanceWithApplicationID "12345"

    # setup view controllers, adding an invite button to them
    rootViewController = MainViewController.new
    navigationController = UINavigationController.alloc.initWithRootViewController(rootViewController)
    openInvitePageButton = UIBarButtonItem.alloc.initWithTitle("Invite",
      style:UIBarButtonItemStylePlain, 
      target: self,
      action: :launch_mave_invite_page,
    )
    navigationController.navigationBar.topItem.rightBarButtonItem = openInvitePageButton

    # present view controller
    @window = UIWindow.alloc.initWithFrame(UIScreen.mainScreen.bounds)
    @window.rootViewController = navigationController
    @window.makeKeyAndVisible

    true
  end

  def launch_mave_invite_page
    puts "Displaying Mave invite page!"
    # identify a fake user
    user = MAVEUserData.alloc.initWithUserID("123", firstName:"Danny", lastName:"Cosson")
    MaveSDK.sharedInstance.identifyUser user

    # present invite page
    MaveSDK.sharedInstance.presentInvitePageModallyWithBlock(lambda do |inviteController|
      @window.rootViewController.presentViewController(inviteController, animated:true, completion:nil)
    end, dismissBlock: lambda do |controller, numberInvitesSent|
      controller.dismissViewControllerAnimated(true, completion:nil)
    end, inviteContext: "default")
  end
end
