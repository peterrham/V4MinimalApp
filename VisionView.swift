//
//  ContentView 2.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/5/24.
//


import SwiftUI
import PhotosUI
import Vision

struct VisionView: View {
    @State private var selectedImage: UIImage? = nil
    @State private var recognizedObjects: [String] = []
    @State private var showImagePicker = false

    var body: some View {
        VStack {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 300)
                
                List(recognizedObjects, id: \.self) { object in
                    Text(object)
                }
            } else {
                Text("Select an image to recognize objects")
                    .font(.headline)
                    .padding()
            }

            Button("Choose Photo") {
                showImagePicker = true
            }
            .padding()
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImage: $selectedImage, onImagePicked: detectObjects)
            }
        }
    }

    func detectObjects(in image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        
        let model: VNCoreMLModel
        do {
            // Load a pretrained Core ML model for object recognition
            model = try VNCoreMLModel(for: MobileNetV2().model)
        } catch {
            print("Failed to load model: \(error)")
            return
        }

        // Create a request for object recognition
        let request = VNCoreMLRequest(model: model) { request, error in
            if let error = error {
                print("Failed to perform recognition: \(error)")
                return
            }
            processResults(request.results)
        }

        // Perform the request on the chosen image
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform request: \(error)")
        }
    }

    func processResults(_ results: [Any]?) {
        recognizedObjects.removeAll()
        
        guard let observations = results as? [VNRecognizedObjectObservation] else { return }
        
        for observation in observations {
            let topLabel = observation.labels.first?.identifier ?? "Unknown"
            recognizedObjects.append(topLabel)
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    var onImagePicked: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }

            provider.loadObject(ofClass: UIImage.self) { image, error in
                if let uiImage = image as? UIImage {
                    DispatchQueue.main.async {
                        self.parent.selectedImage = uiImage
                        self.parent.onImagePicked(uiImage)
                    }
                }
            }
        }
    }
}
