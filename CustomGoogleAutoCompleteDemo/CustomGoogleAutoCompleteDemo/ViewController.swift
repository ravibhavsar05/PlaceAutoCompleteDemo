
import UIKit
let GoogleMapsAPIServerKey = "YOUR_API_KEY"

class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
    
    @IBAction func action(_ sender: Any) {
        let vc = UIStoryboard.init(name: "Main", bundle: Bundle.main).instantiateViewController(withIdentifier: "AutoComplete") as! AutoComplete
        vc.delegate = self
        self.navigationController?.pushViewController(vc, animated: true)
    }
}

extension ViewController:  GooglePlacesAutocompleteViewControllerDelegate{
    func viewController(didAutocompleteWith place: PlaceDetails) {
        print(place)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { (timer) in
            
            let alert = UIAlertController(title: "Description", message: place.description,preferredStyle: UIAlertController.Style.alert)
            alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: {(_: UIAlertAction!) in
            }))
            self.present(alert, animated: true, completion: nil)
            
        }
    }
}
