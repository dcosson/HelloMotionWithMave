# Hello Motion with Mave

An example RubyMotion app using the Mave invite page

## Steps to create this project

1. `motion create HelloMotionWithMave` then `cd HelloMotionWithMave`

2. add "motion-cocoapods" to Gemfile

3. add the MaveSDK pod to the Rakefile (see the Rakefile for code)

4. `bundle install`

5. `bundle exec pod:install`

6. `cp -r ./vendor/Pods/.build/MaveSDK.bundle ./resources/`

7. `bundle exec rake`

Step 6 is of particular note, usually Cocoapods will put the bundle into the right place to be used in the app but motion-cocoapods has a bug where this does not happen. So until that gets fixed, every time your run a pod:update or pod:install you should copy the MaveSDK.bundle (and bundles for any other cocoapods you use) to make sure you have the updated resources.
