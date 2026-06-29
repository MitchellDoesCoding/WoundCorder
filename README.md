# WoundCorder

**WoundCorder** is an iOS-based wound documentation and measurement platform designed to make wound assessment more objective, repeatable, and practical outside specialty care.

Current wound documentation often depends on subjective visual judgment, manual ruler measurements, and inconsistent clinical notes. This creates problems when wounds are monitored over time, especially in home health, skilled nursing facilities, primary care, and other settings where specialty wound care may not be immediately available.

WoundCorder combines **LiDAR-based 3D wound measurement**, **image-based wound documentation**, and **AI-assisted analysis** to help standardize wound tracking while keeping the workflow simple enough for real-world use.

---

## Problem

Chronic wounds are difficult to manage because clinicians need to know whether a wound is truly improving, worsening, or staying the same. Traditional wound measurement methods usually rely on:

- Manual length and width measurements
- Visual estimates of depth and tissue type
- Inconsistent photo documentation
- Subjective descriptions in clinical notes

These methods can miss important changes in wound volume, depth, surface area, and appearance. Small documentation errors can also become clinically important when care decisions depend on whether a wound is healing.

The core problem is not just taking wound photos.  
The core problem is turning those photos into reliable, repeatable clinical information.

---

## Project Overview

WoundCorder is built as a mobile-first wound assessment tool that uses the hardware already available on modern iPhones and iPads.

The app is designed to support:

- 3D wound measurement using Apple LiDAR
- Area, perimeter, and volume estimation
- Structured wound image capture
- AI-assisted wound characterization
- On-device or privacy-preserving analysis workflows
- Longitudinal wound tracking over time

The goal is not to replace clinicians. The goal is to give clinicians better measurement data and more consistent documentation.

---

## Key Features

### LiDAR-Based Wound Measurement

WoundCorder uses Apple’s ARKit and LiDAR capabilities to estimate wound geometry in three dimensions.

Planned and implemented measurement features include:

- Wound surface area
- Wound perimeter
- Depth-point selection
- Approximate wound volume
- 3D mesh visualization
- Manual boundary correction
- Exportable measurement data

### Image-Based Documentation

The app supports wound image capture and structured visual documentation so wounds can be compared over time.

Potential documentation fields include:

- Wound location
- Wound size
- Wound depth
- Drainage appearance
- Tissue type
- Surrounding skin changes
- Signs of possible infection or deterioration

### AI-Assisted Analysis

WoundCorder explores the use of vision-language models and wound-specific AI tools to assist with structured wound documentation.

The AI layer is intended to support internal review and clinician-facing workflows, not provide unsupervised diagnosis or treatment recommendations.

Potential AI outputs include:

- Structured wound description
- Measurement summary
- Documentation quality check
- Change-over-time summary
- Referral or eConsult support

---

## Technical Stack

### Mobile App

- Swift
- SwiftUI / UIKit
- ARKit
- RealityKit / SceneKit
- Vision framework
- Core ML
- LiDAR depth sensing

### Backend / API

- Node.js
- Express
- REST API endpoints for wound image analysis
- Optional external AI model integration

### Machine Learning / Computer Vision

- Wound segmentation
- Image preprocessing
- Boundary detection
- Vision-language model prompting
- Structured JSON output for wound documentation

---

## Current Development Status

WoundCorder is an active prototype. Current work focuses on improving:

- Measurement accuracy
- Wound boundary detection
- Depth and volume estimation
- User interface flow
- AI-assisted wound documentation
- Clinical safety and reliability

Earlier versions showed promising area measurement performance, but further validation is still needed before clinical deployment.

---

## Example Workflow

1. Open the WoundCorder app.
2. Position the device over the wound.
3. Capture a wound image and LiDAR scan.
4. Mark or refine the wound boundary.
5. Select a depth reference point if needed.
6. Generate wound measurements.
7. Review structured wound documentation.
8. Save or export the wound record for follow-up.

---

## Clinical Use Case

WoundCorder is designed for settings where wound monitoring needs to be more consistent and scalable, including:

- Home health
- Skilled nursing facilities
- Primary care
- Wound care clinics
- Remote patient monitoring
- eConsult workflows
- Care coordination between providers

The app is especially relevant for chronic wounds where tracking healing over time is critical.

---

## Safety and Limitations

WoundCorder is a prototype and is not currently intended to replace clinical judgment.

Important limitations include:

- Measurement accuracy depends on image quality, lighting, scan angle, and device positioning.
- AI-generated wound descriptions may contain errors and require clinician review.
- The app should not be used as a standalone diagnostic tool.
- Clinical validation is required before use in medical decision-making.
- Wound infection, ischemia, necrosis, or deterioration should be assessed by qualified clinicians.

---

## Research Direction

This project is also connected to broader research questions in medical AI and physical-world computer vision, including:

- How reliably can AI models interpret surface medical photographs?
- Can mobile depth sensing improve wound measurement compared with 2D images?
- How should wound images be standardized for AI-assisted documentation?
- What failure modes occur when vision-language models analyze clinical images?
- How can AI tools support clinicians without creating unsafe automation?

---

## Roadmap

Planned development areas include:

- Improved wound segmentation
- More robust LiDAR mesh processing
- Calibration marker support
- Longitudinal wound tracking dashboard
- Structured PDF wound reports
- On-device model optimization
- eConsult integration
- Clinical validation dataset
- Privacy-preserving analysis pipeline

---

## Repository Structure

```text
WoundCorder/
├── iOS-App/
│   ├── ARKit measurement views
│   ├── wound boundary tools
│   ├── LiDAR mesh processing
│   └── image capture workflow
│
├── Backend/
│   ├── Express API server
│   ├── image upload endpoint
│   └── AI analysis endpoint
│
├── Models/
│   ├── wound segmentation models
│   └── model configuration files
│
├── Docs/
│   ├── clinical workflow notes
│   ├── measurement validation notes
│   └── safety documentation
│
└── README.md
