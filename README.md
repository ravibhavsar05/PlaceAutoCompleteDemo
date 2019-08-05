# PlaceAutoCompleteDemo
This demo provides google autocomplete demo with custom UI &amp; current location.

 ## Requirements

- iOS 11.0+
- Xcode 10.1+
- Swift 5

## Usage
- PlaceAutoCompleteDemo consists of custom google place autocomplete with current location in it. It contains helper class for the UI & the webcall.
- Navigate to the helper class called **AutoComplete** & search any location or one can use the current location. It will fetch the details & redirect back to the previous UI.

## ViewController.swift 

     // Add code in viewDidload or any suitable action method.

     let vc = UIStoryboard.init(name: "Main", bundle: Bundle.main).instantiateViewController(withIdentifier: "AutoComplete") as! AutoComplete
     vc.delegate = self
     self.navigationController?.pushViewController(vc, animated: true)
    
    // Place the delegate in ViewController.swift
    extension ViewController:  GooglePlacesAutocompleteViewControllerDelegate{
     func viewController(didAutocompleteWith place: PlaceDetails) {
        print(place)
      }
    }

## Output
![Location - Animated gif demo](CustomGoogleAutoCompleteDemo/Location.gif)
