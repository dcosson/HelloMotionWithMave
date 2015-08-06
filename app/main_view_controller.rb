class MainViewController < UIViewController

  def loadView
    self.view = UIView.new
  end

  def viewDidLoad
    self.title = "Hello RubyMotion"
    self.view.backgroundColor = UIColor.whiteColor
  end

end
