# StockFlow

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![SQLite](https://img.shields.io/badge/sqlite-%2307405e.svg?style=for-the-badge&logo=sqlite&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)

StockFlow is a locally-hosted, privacy-first desktop application designed specifically for Taiwanese stock market investors. It provides precise accounting, portfolio management, and advanced data visualization without relying on any external cloud databases.

> **Note / 注意：** > The application interface is currently exclusively in **Traditional Chinese (繁體中文版)**.

## Key Features

* **100% Offline & Privacy-First:** All financial data is stored locally using SQLite. No user data is ever uploaded to the cloud.
* **Broker-Level EOD Settlement Engine:** Accurately processes Day Trades (當沖), retained Day Trade positions, and spot trading (現股) with Chronological Replay capabilities to ensure cost basis is always perfectly calculated, even when backdating historical entries.
* **Taiwan Market-Specific Fee Logic:** Implements the dual-track minimum fee system (NT$20 for whole shares, NT$1 for fractional shares) and handles customized broker discount rates, mirroring actual broker statements flawlessly.
* **Advanced Data Visualization:** Features interactive pie charts for asset allocation and bar charts for realized/unrealized P&L analysis, built with Syncfusion UI.
* **Self-Contained Portable App:** Designed to be a portable Windows application. Users can carry their accounting database and the executable on a USB drive.

## Current Limitations

Please note that this application currently **DOES NOT SUPPORT** the following advanced trading types:
* Margin Trading (融資) & Short Selling (融券)
* Securities Lending (借券)
* Futures (期貨) & Options (選擇權)

*(Reason: The settlement and maintenance margin calculations for these derivatives are highly complex. This app currently focuses purely on providing the most accurate spot and day-trading settlement experience.)*

## Screenshots

| Dashboard | Profit Analysis |
| :---: | :---: |
| ![Dashboard](replace_with_your_dashboard_image_url_here) | ![Profit Analysis](replace_with_your_chart_image_url_here) |
| *Clear overview of asset allocation and net P&L.* | *Interactive charts for realized profit and hidden costs.* |

## Tech Stack

* **Framework:** [Flutter](https://flutter.dev/) (Desktop / Windows)
* **Language:** Dart
* **Database:** SQLite (`sqflite_common_ffi`)
* **State Management:** Provider
* **UI & Charts:** `syncfusion_flutter_charts`

## Getting Started

To build and run this project locally:

1. **Clone the repository:**
   ```bash
   git clone https://github.com/whatever961/StockFlow.git
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the application:**
   ```bash
   flutter run -d windows
   ```

4. **Build Release (Portable Windows App):**
   ```bash
   flutter build windows --release
   ```

## Acknowledgments & Third-Party Licenses

* **Syncfusion Flutter Charts**: This project utilizes the excellent [Syncfusion Flutter Charts](https://pub.dev/packages/syncfusion_flutter_charts) package for data visualization. It is used here under the [Syncfusion Community License](https://www.syncfusion.com/products/communitylicense). Please note that if you fork or reuse this project, you must ensure you meet the criteria for their Community License or obtain a commercial license directly from Syncfusion.

## Disclaimer
This software is for personal accounting and educational purposes only. It does not constitute financial advice. The developer assumes no responsibility for any trading losses or calculation discrepancies.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
