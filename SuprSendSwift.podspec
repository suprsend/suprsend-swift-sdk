Pod::Spec.new do |spec|
  spec.name         = "SuprSendSwift"
  spec.version      = "1.0.0"
  spec.summary      = "SuprSend Swift SDK."
  spec.description  = <<-DESC
  SuprSend is a robust notification infrastructure that helps you deploy multi-channel product notifications effortlessly and take care of user experience.
                   DESC

  spec.homepage     = "https://github.com/suprsend/suprsend-swift-sdk.git"
  spec.license      = { :type => "MIT" }
  spec.author             = { "Ram Suthar" => "reallyram@gmail.com" }

  spec.ios.deployment_target = "15.0"
  spec.osx.deployment_target = "12.0"

  spec.source       = { :git => "https://github.com/suprsend/suprsend-swift-sdk.git", :tag => "#{spec.version}" }
  spec.source_files  = "Sources/SuprSendSwift/**/*.swift"
  
  spec.dependency "ReachabilitySwift", "~> 5.2.4"
  
  spec.requires_arc = true
  spec.swift_version = '5.0'

end
