# Poincaré HRV Visualizer

Real-time visualization of RR-interval dynamics using a Poincaré plot for educational and exploratory purposes. This app runs as a Device App (Watch App) on compatible Garmin devices.

## Features

### Real-Time Poincaré Plot
*   Visualizes the relationship between consecutive RR intervals ($RR_{n}$ vs $RR_{n+1}$).
*   Calculates and displays standard HRV metrics: **SD1**, **SD2**.

### Display Modes
Use the **Select / Menu** button to cycle through the following 5 display modes:

1.  **Wide Mode (Default)**
    *   Fixed Range: **60 - 130 BPM**.
    *   Good for general monitoring during mild activity.

2.  **Zoom Mode**
    *   Fixed Range: **60 - 90 BPM**.
    *   Focused view for resting or low-variability states.

3.  **Auto Mode**
    *   **Dynamic Scaling**: Automatically adjusts the axis range based on the minimum and maximum RR intervals in the buffer.
    *   Ensures all points are visible.

4.  **ASM Mode (Autonomic State Map)**
    *   **Concept**: Visualizes the autonomic state based on SD1 (Parasympathetic) and SD2 (Sympathetic/Overall) indices.
    *   **Dynamic Center**: The crosshair center is determined by the **Long Term Average** (last 60 beats).
    *   **Current State**: A filled dot shows the **Short Term Average** (last 15 beats), visualizing your current trend relative to the recent baseline.
    *   **Grid**: Reference grid lines intersect at the moving average center.

5.  **Energy vs Balance Mode**
    *   **X-Axis**: **Balance** ($\frac{SD1}{SD2}$). Range: 0.0 (Rigid) to 1.2 (Flexible).
    *   **Y-Axis**: **Total Energy** ($SD1 \times SD2$). **Log Scale** mainly from 10 to 100,000. Labels: Weak to Robust.
    *   **Trailing Tail**: Shows the trajectory of the last 5 minutes (approx. 300 beats) to visualize changes in autonomic balance and energy over time.

### Activity Recording
*   **FIT File Support**: The app records an activity session when running.
*   **Custom Fields**: **SD1** and **SD2** values are computed in real-time and written to the activity FIT file for post-analysis.
*   **60s Rolling History**: All displayed metrics (Poincaré points, ASM trace, Energy-Balance trail) keep only the last 60 seconds of recorded data for responsive real-time tracking.
*   **Signal Indicator**: A status dot is now shown in each display mode (green/yellow/red) for HR signal quality in real-time.

## Usage
*   **Start**: Launch the app. It will automatically search for a Heart Rate monitor.
*   **Switch Modes**: Press the **Select** (Enter) or **Menu** button (depending on device layout) to cycle through the display modes.
*   **Exit/Save**: Press **Back** to stop the session and exit. The activity will be saved.

## Disclaimer
**This app is designed for educational, research, and personal exploration purposes only.**
It does not provide medical advice, diagnosis, or health assessment. The displayed values are not intended to indicate stress, recovery, fitness, or health status. Users should not make medical or training decisions based solely on this app.