import cv2

WINDOW_TITLE = "CSI Camera"
DEFAULT_FLIP_METHOD = 0
EXIT_KEYS = {27, ord("q")}  # ESC or q


def gstreamer_pipeline(
    sensor_id: int = 0,
    capture_width: int = 1920,
    capture_height: int = 1080,
    display_width: int = 1920,
    display_height: int = 1080,
    framerate: int = 60,
    flip_method: int = DEFAULT_FLIP_METHOD,
) -> str:
    """Build a GStreamer pipeline string for CSI camera capture."""
    return (
        "nvarguscamerasrc sensor-id=%d ! "
        "video/x-raw(memory:NVMM), width=(int)%d, height=(int)%d, framerate=(fraction)%d/1 ! "
        "nvvidconv flip-method=%d ! "
        "video/x-raw, width=(int)%d, height=(int)%d, format=(string)BGRx ! "
        "videoconvert ! "
        "video/x-raw, format=(string)BGR ! appsink"
        % (
            sensor_id,
            capture_width,
            capture_height,
            framerate,
            flip_method,
            display_width,
            display_height,
        )
    )


def show_camera(flip_method: int = DEFAULT_FLIP_METHOD) -> None:
    """Open the camera feed and display frames until the window closes or user exits."""
    pipeline = gstreamer_pipeline(flip_method=flip_method)
    print(pipeline)

    video_capture = cv2.VideoCapture(pipeline, cv2.CAP_GSTREAMER)
    if not video_capture.isOpened():
        print("Error: Unable to open camera")
        return

    try:
        cv2.namedWindow(WINDOW_TITLE, cv2.WINDOW_AUTOSIZE)
        while True:
            ret_val, frame = video_capture.read()
            if not ret_val:
                print("Warning: Failed to read frame from camera")
                break

            # Under GTK+ (Jetson default), WND_PROP_VISIBLE is unreliable.
            if cv2.getWindowProperty(WINDOW_TITLE, cv2.WND_PROP_AUTOSIZE) < 0:
                break

            cv2.imshow(WINDOW_TITLE, frame)
            key_code = cv2.waitKey(10) & 0xFF
            if key_code in EXIT_KEYS:
                break
    finally:
        video_capture.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    show_camera()
