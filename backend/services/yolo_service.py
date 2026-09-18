from ultralytics import YOLO


# Load YOLO model
model = YOLO("yolo11n.pt")


def detect_objects(image_path):

    results = model(image_path)

    objects = []

    for result in results:

        boxes = result.boxes

        for box in boxes:

            class_id = int(box.cls[0])
            confidence = float(box.conf[0])

            # Bounding box coordinates
            x1, y1, x2, y2 = box.xyxy[0].tolist()

            object_name = model.names[class_id]

            objects.append({
                "name": object_name,
                "confidence": round(confidence, 2),
                "bbox": [
                    int(x1),
                    int(y1),
                    int(x2),
                    int(y2)
                ]
            })

    return {
        "objects": objects
    }
