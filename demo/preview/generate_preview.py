import os
import json

html_content = r'''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Buildto — Construction Materials Marketplace (Client Demo Prototype)</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    :root {
      --primary: #002B5B;
      --primary-dark: #001C3D;
      --primary-light: #0A3D78;
      --secondary: #F59E0B;
      --secondary-hover: #D97706;
      --bg: #F8FAFC;
      --surface: #FFFFFF;
      --text-main: #0F172A;
      --text-muted: #64748B;
      --border: #E2E8F0;
      --success: #10B981;
      --danger: #EF4444;
      --info: #0284C7;
      --radius: 12px;
      --shadow-sm: 0 1px 3px rgba(0,0,0,0.06);
      --shadow-md: 0 4px 6px -1px rgba(0,0,0,0.08);
      --shadow-lg: 0 10px 15px -3px rgba(0,0,0,0.1);
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, sans-serif;
      -webkit-tap-highlight-color: transparent;
    }

    body {
      background: #0B132B;
      color: var(--text-main);
      display: flex;
      flex-direction: column;
      align-items: center;
      min-height: 100vh;
      padding: 20px 10px;
    }

    /* Top Demo Header Bar */
    .demo-bar {
      width: 100%;
      max-width: 1100px;
      background: rgba(255, 255, 255, 0.08);
      backdrop-filter: blur(12px);
      border: 1px solid rgba(255, 255, 255, 0.15);
      border-radius: 16px;
      padding: 12px 20px;
      margin-bottom: 20px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      color: white;
      box-shadow: 0 8px 32px rgba(0,0,0,0.3);
    }
    .demo-title-group h1 {
      font-size: 1.15rem;
      font-weight: 700;
      display: flex;
      align-items: center;
      gap: 10px;
      letter-spacing: -0.3px;
    }
    .badge-demo {
      background: var(--secondary);
      color: #000;
      font-size: 0.7rem;
      font-weight: 800;
      padding: 3px 8px;
      border-radius: 20px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    .demo-title-group p {
      font-size: 0.8rem;
      color: #94A3B8;
      margin-top: 2px;
    }
    .screen-selector-container {
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .screen-select {
      background: #1E293B;
      color: #F8FAFC;
      border: 1px solid #475569;
      border-radius: 8px;
      padding: 8px 12px;
      font-size: 0.85rem;
      font-weight: 600;
      outline: none;
      cursor: pointer;
    }
    .screen-select:focus {
      border-color: var(--secondary);
    }

    /* Main Container with Mobile Mockup and Side Inspector */
    .preview-layout {
      display: flex;
      gap: 30px;
      align-items: flex-start;
      justify-content: center;
      width: 100%;
      max-width: 1150px;
    }

    /* Mobile Device Frame */
    .phone-frame {
      width: 400px;
      height: 840px;
      background: #000;
      border-radius: 46px;
      padding: 12px;
      box-shadow: 0 25px 60px rgba(0,0,0,0.6), 0 0 0 2px #334155;
      position: relative;
      flex-shrink: 0;
    }

    .phone-screen {
      width: 100%;
      height: 100%;
      background: var(--bg);
      border-radius: 36px;
      overflow: hidden;
      display: flex;
      flex-direction: column;
      position: relative;
    }

    /* Phone Dynamic Island / Notch */
    .phone-notch {
      position: absolute;
      top: 8px;
      left: 50%;
      transform: translateX(-50%);
      width: 110px;
      height: 24px;
      background: #000;
      border-radius: 20px;
      z-index: 999;
    }

    /* Mobile Status Bar */
    .status-bar {
      height: 40px;
      padding: 10px 20px 0;
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 0.75rem;
      font-weight: 700;
      color: #0F172A;
      background: var(--surface);
      z-index: 90;
      user-select: none;
    }

    /* Screen Views Container */
    .screen-viewport {
      flex: 1;
      overflow-y: auto;
      overflow-x: hidden;
      display: flex;
      flex-direction: column;
      position: relative;
      scroll-behavior: smooth;
    }
    .screen-viewport::-webkit-scrollbar {
      width: 4px;
    }
    .screen-viewport::-webkit-scrollbar-thumb {
      background: #CBD5E1;
      border-radius: 4px;
    }

    /* Individual Screen Containers */
    .app-screen {
      display: none;
      flex-direction: column;
      min-height: 100%;
      animation: fadeIn 0.15s ease-in-out;
    }
    .app-screen.active {
      display: flex;
    }

    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(4px); }
      to { opacity: 1; transform: translateY(0); }
    }

    /* Bottom Navigation Bar */
    .bottom-nav {
      height: 64px;
      background: var(--surface);
      border-top: 1px solid var(--border);
      display: flex;
      align-items: center;
      justify-content: space-around;
      padding: 0 10px;
      z-index: 80;
      box-shadow: 0 -4px 10px rgba(0,0,0,0.03);
    }
    .nav-item {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 3px;
      font-size: 0.7rem;
      font-weight: 600;
      color: var(--text-muted);
      cursor: pointer;
      position: relative;
      padding: 6px 12px;
      border-radius: 8px;
      transition: all 0.2s;
    }
    .nav-item svg {
      width: 22px;
      height: 22px;
      fill: none;
      stroke: currentColor;
      stroke-width: 2;
    }
    .nav-item.active {
      color: var(--primary);
    }
    .nav-badge {
      position: absolute;
      top: 2px;
      right: 14px;
      background: var(--secondary);
      color: #000;
      font-size: 0.65rem;
      font-weight: 800;
      min-width: 16px;
      height: 16px;
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 0 4px;
    }

    /* Reusable App Components */
    .app-header {
      background: var(--surface);
      padding: 12px 16px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid var(--border);
      position: sticky;
      top: 0;
      z-index: 50;
    }
    .header-logo-group {
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .logo-icon-box {
      width: 32px;
      height: 32px;
      background: var(--primary);
      color: var(--secondary);
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-weight: 900;
      font-size: 1.1rem;
    }
    .header-brand {
      font-size: 1.1rem;
      font-weight: 800;
      color: var(--primary);
      letter-spacing: -0.5px;
    }
    .header-tagline {
      font-size: 0.65rem;
      color: var(--text-muted);
      font-weight: 600;
    }
    .header-actions {
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .header-btn {
      width: 36px;
      height: 36px;
      border-radius: 50%;
      background: #F1F5F9;
      border: none;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      color: var(--text-main);
      position: relative;
    }
    .header-btn svg {
      width: 18px;
      height: 18px;
      stroke: currentColor;
      fill: none;
      stroke-width: 2;
    }
    .header-btn-badge {
      position: absolute;
      top: 4px;
      right: 4px;
      width: 8px;
      height: 8px;
      background: var(--secondary);
      border-radius: 50%;
    }

    /* Search Bar */
    .search-box {
      margin: 12px 16px;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 10px 14px;
      display: flex;
      align-items: center;
      gap: 10px;
      box-shadow: var(--shadow-sm);
    }
    .search-box svg {
      width: 18px;
      height: 18px;
      stroke: var(--text-muted);
      stroke-width: 2;
      fill: none;
    }
    .search-box input {
      border: none;
      outline: none;
      width: 100%;
      font-size: 0.85rem;
      color: var(--text-main);
      background: transparent;
    }

    /* Banners */
    .hero-banner {
      margin: 0 16px 16px;
      height: 145px;
      border-radius: 14px;
      overflow: hidden;
      position: relative;
      background: #0F172A;
      box-shadow: var(--shadow-md);
      cursor: pointer;
    }
    .hero-banner img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      opacity: 0.85;
    }
    .hero-banner-overlay {
      position: absolute;
      inset: 0;
      background: linear-gradient(90deg, rgba(0, 43, 91, 0.9) 0%, rgba(0, 43, 91, 0.4) 100%);
      padding: 16px;
      display: flex;
      flex-direction: column;
      justify-content: center;
      color: white;
    }
    .hero-banner-tag {
      background: var(--secondary);
      color: #000;
      font-size: 0.65rem;
      font-weight: 800;
      padding: 2px 8px;
      border-radius: 4px;
      width: fit-content;
      margin-bottom: 6px;
      text-transform: uppercase;
    }
    .hero-banner-title {
      font-size: 1.1rem;
      font-weight: 800;
      line-height: 1.25;
      margin-bottom: 4px;
    }
    .hero-banner-sub {
      font-size: 0.75rem;
      color: #E2E8F0;
    }

    /* Section Headers */
    .section-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 4px 16px 10px;
    }
    .section-title {
      font-size: 0.95rem;
      font-weight: 700;
      color: var(--primary);
    }
    .section-link {
      font-size: 0.75rem;
      font-weight: 600;
      color: var(--secondary-hover);
      cursor: pointer;
    }

    /* Horizontal Category Strip */
    .category-strip {
      display: flex;
      gap: 12px;
      padding: 0 16px 16px;
      overflow-x: auto;
    }
    .category-strip::-webkit-scrollbar { display: none; }
    .cat-pill {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 6px;
      cursor: pointer;
      flex-shrink: 0;
    }
    .cat-pill-icon {
      width: 58px;
      height: 58px;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 14px;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: var(--shadow-sm);
      overflow: hidden;
      padding: 8px;
    }
    .cat-pill-icon img {
      width: 100%;
      height: 100%;
      object-fit: contain;
    }
    .cat-pill-label {
      font-size: 0.72rem;
      font-weight: 600;
      color: var(--text-main);
      text-align: center;
      max-width: 64px;
      line-height: 1.1;
    }

    /* Horizontal Suppliers */
    .supplier-scroll {
      display: flex;
      gap: 12px;
      padding: 0 16px 16px;
      overflow-x: auto;
    }
    .supplier-scroll::-webkit-scrollbar { display: none; }
    .supplier-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 12px;
      min-width: 210px;
      flex-shrink: 0;
      box-shadow: var(--shadow-sm);
      cursor: pointer;
    }
    .sup-badge {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      background: #ECFDF5;
      color: #065F46;
      font-size: 0.65rem;
      font-weight: 700;
      padding: 2px 6px;
      border-radius: 4px;
      margin-bottom: 6px;
    }
    .sup-name {
      font-size: 0.85rem;
      font-weight: 700;
      color: var(--primary);
      margin-bottom: 4px;
    }
    .sup-meta {
      font-size: 0.7rem;
      color: var(--text-muted);
      display: flex;
      align-items: center;
      gap: 8px;
    }

    /* Product Grid */
    .product-grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 12px;
      padding: 0 16px 16px;
    }
    .product-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 14px;
      overflow: hidden;
      display: flex;
      flex-direction: column;
      box-shadow: var(--shadow-sm);
      cursor: pointer;
      position: relative;
    }
    .prod-img-box {
      height: 130px;
      background: #F1F5F9;
      position: relative;
      overflow: hidden;
    }
    .prod-img-box img {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }
    .prod-tag {
      position: absolute;
      top: 8px;
      left: 8px;
      background: rgba(0, 43, 91, 0.9);
      color: white;
      font-size: 0.6rem;
      font-weight: 700;
      padding: 2px 6px;
      border-radius: 4px;
    }
    .prod-wish {
      position: absolute;
      top: 8px;
      right: 8px;
      width: 28px;
      height: 28px;
      border-radius: 50%;
      background: rgba(255, 255, 255, 0.9);
      display: flex;
      align-items: center;
      justify-content: center;
      border: none;
      cursor: pointer;
    }
    .prod-wish svg {
      width: 14px;
      height: 14px;
      stroke: var(--text-muted);
      fill: none;
      stroke-width: 2;
    }
    .prod-info {
      padding: 10px;
      display: flex;
      flex-direction: column;
      flex: 1;
    }
    .prod-supplier {
      font-size: 0.65rem;
      font-weight: 600;
      color: var(--text-muted);
      margin-bottom: 2px;
    }
    .prod-title {
      font-size: 0.8rem;
      font-weight: 700;
      color: var(--text-main);
      line-height: 1.25;
      margin-bottom: 6px;
      min-height: 32px;
    }
    .prod-price-row {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      margin-top: auto;
      margin-bottom: 8px;
    }
    .prod-price {
      font-size: 0.95rem;
      font-weight: 800;
      color: var(--primary);
    }
    .prod-unit {
      font-size: 0.68rem;
      color: var(--text-muted);
      font-weight: 500;
    }
    .btn-add-cart {
      background: var(--primary);
      color: white;
      border: none;
      border-radius: 8px;
      padding: 7px 10px;
      font-size: 0.75rem;
      font-weight: 700;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 6px;
      transition: background 0.2s;
    }
    .btn-add-cart:hover {
      background: var(--primary-light);
    }
    .btn-qty-control {
      display: flex;
      align-items: center;
      justify-content: space-between;
      background: #F1F5F9;
      border-radius: 8px;
      padding: 2px 6px;
    }
    .qty-btn {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 6px;
      width: 26px;
      height: 26px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-weight: 800;
      font-size: 0.9rem;
      cursor: pointer;
      color: var(--primary);
    }
    .qty-text {
      font-size: 0.8rem;
      font-weight: 800;
      color: var(--primary);
    }

    /* Screen Top Navigation Bar (Back, Title, Actions) */
    .nav-header {
      background: var(--surface);
      padding: 12px 16px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid var(--border);
      position: sticky;
      top: 0;
      z-index: 40;
    }
    .back-btn {
      width: 34px;
      height: 34px;
      border-radius: 8px;
      background: #F1F5F9;
      border: none;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      color: var(--primary);
    }
    .back-btn svg {
      width: 18px;
      height: 18px;
      stroke: currentColor;
      fill: none;
      stroke-width: 2.5;
    }
    .nav-header-title {
      font-size: 0.95rem;
      font-weight: 800;
      color: var(--primary);
    }

    /* Filter Chips */
    .filter-chips {
      display: flex;
      gap: 8px;
      padding: 10px 16px;
      overflow-x: auto;
      background: var(--surface);
      border-bottom: 1px solid var(--border);
    }
    .filter-chips::-webkit-scrollbar { display: none; }
    .chip {
      padding: 6px 14px;
      border-radius: 20px;
      font-size: 0.75rem;
      font-weight: 600;
      background: #F1F5F9;
      color: var(--text-muted);
      border: 1px solid var(--border);
      cursor: pointer;
      white-space: nowrap;
    }
    .chip.active {
      background: var(--primary);
      color: white;
      border-color: var(--primary);
    }

    /* Product Detail Screen */
    .detail-img-box {
      height: 240px;
      background: #FFF;
      position: relative;
    }
    .detail-img-box img {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }
    .detail-body {
      padding: 16px;
      background: var(--surface);
      border-radius: 20px 20px 0 0;
      margin-top: -16px;
      position: relative;
    }
    .specs-grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 10px;
      margin: 14px 0;
    }
    .spec-item {
      background: #F8FAFC;
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 10px;
    }
    .spec-label {
      font-size: 0.68rem;
      color: var(--text-muted);
      font-weight: 600;
      margin-bottom: 2px;
    }
    .spec-value {
      font-size: 0.82rem;
      color: var(--primary);
      font-weight: 800;
    }

    /* Cart Screen */
    .cart-item-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 12px;
      margin: 8px 16px;
      display: flex;
      gap: 12px;
      align-items: center;
    }
    .cart-item-img {
      width: 64px;
      height: 64px;
      border-radius: 8px;
      object-fit: cover;
      background: #F1F5F9;
    }
    .cart-item-info {
      flex: 1;
    }
    .cart-bill-box {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 14px;
      margin: 14px 16px;
    }
    .bill-row {
      display: flex;
      justify-content: space-between;
      font-size: 0.8rem;
      color: var(--text-muted);
      margin-bottom: 8px;
    }
    .bill-row.total {
      font-size: 0.95rem;
      font-weight: 800;
      color: var(--primary);
      border-top: 1px dashed var(--border);
      padding-top: 10px;
      margin-bottom: 0;
    }

    /* Primary CTA Button */
    .btn-primary-cta {
      background: var(--primary);
      color: white;
      border: none;
      border-radius: 12px;
      padding: 14px 20px;
      font-size: 0.9rem;
      font-weight: 800;
      display: flex;
      align-items: center;
      justify-content: space-between;
      cursor: pointer;
      box-shadow: var(--shadow-md);
      transition: background 0.2s;
    }
    .btn-primary-cta:hover {
      background: var(--primary-light);
    }
    .btn-primary-cta:disabled {
      background: #94A3B8;
      cursor: not-allowed;
    }

    /* Order Placed Success Screen */
    .success-container {
      flex: 1;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 24px;
      text-align: center;
    }
    .success-circle {
      width: 80px;
      height: 80px;
      background: #ECFDF5;
      border: 2px solid var(--success);
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      color: var(--success);
      margin-bottom: 16px;
      animation: scaleIn 0.3s ease-out;
    }
    @keyframes scaleIn {
      from { transform: scale(0.5); opacity: 0; }
      to { transform: scale(1); opacity: 1; }
    }
    .order-id-badge {
      background: #F1F5F9;
      border: 1px solid var(--border);
      padding: 6px 14px;
      border-radius: 20px;
      font-size: 0.85rem;
      font-weight: 800;
      color: var(--primary);
      margin: 12px 0 20px;
    }

    /* Timeline in Order Tracking */
    .tracking-timeline {
      padding: 16px;
      background: var(--surface);
      border-radius: 14px;
      margin: 14px 16px;
      border: 1px solid var(--border);
    }
    .timeline-step {
      display: flex;
      gap: 12px;
      position: relative;
      padding-bottom: 20px;
    }
    .timeline-step:last-child {
      padding-bottom: 0;
    }
    .timeline-step::after {
      content: '';
      position: absolute;
      left: 11px;
      top: 24px;
      bottom: 0;
      width: 2px;
      background: var(--border);
    }
    .timeline-step:last-child::after { display: none; }
    .timeline-step.completed::after { background: var(--success); }
    .timeline-icon {
      width: 24px;
      height: 24px;
      border-radius: 50%;
      background: #E2E8F0;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 0.65rem;
      font-weight: 800;
      color: white;
      z-index: 2;
    }
    .timeline-step.completed .timeline-icon {
      background: var(--success);
    }
    .timeline-step.active .timeline-icon {
      background: var(--secondary);
      animation: pulse 1.5s infinite;
    }
    @keyframes pulse {
      0% { box-shadow: 0 0 0 0 rgba(245, 158, 11, 0.4); }
      70% { box-shadow: 0 0 0 8px rgba(245, 158, 11, 0); }
      100% { box-shadow: 0 0 0 0 rgba(245, 158, 11, 0); }
    }

    /* Inspector & Screen Switcher Panel (Right Side) */
    .inspector-panel {
      flex: 1;
      max-width: 480px;
      background: #111827;
      border: 1px solid #374151;
      border-radius: 24px;
      padding: 24px;
      color: white;
      display: flex;
      flex-direction: column;
      gap: 18px;
      box-shadow: 0 20px 40px rgba(0,0,0,0.4);
    }
    .inspector-title {
      font-size: 1.1rem;
      font-weight: 800;
      color: #F8FAFC;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .screen-grid-nav {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 8px;
      max-height: 440px;
      overflow-y: auto;
      padding-right: 4px;
    }
    .screen-grid-nav::-webkit-scrollbar { width: 4px; }
    .screen-grid-nav::-webkit-scrollbar-thumb { background: #4B5563; border-radius: 4px; }
    .screen-btn {
      background: #1F2937;
      border: 1px solid #374151;
      border-radius: 10px;
      padding: 10px;
      font-size: 0.75rem;
      font-weight: 700;
      color: #D1D5DB;
      text-align: left;
      cursor: pointer;
      display: flex;
      flex-direction: column;
      gap: 4px;
      transition: all 0.2s;
    }
    .screen-btn:hover {
      background: #374151;
      border-color: #6B7280;
    }
    .screen-btn.active {
      background: rgba(245, 158, 11, 0.15);
      border-color: var(--secondary);
      color: #F59E0B;
    }
    .screen-num {
      font-size: 0.65rem;
      color: #9CA3AF;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    .screen-btn.active .screen-num {
      color: var(--secondary);
    }

    .info-card {
      background: #1F2937;
      border: 1px solid #374151;
      border-radius: 12px;
      padding: 14px;
      font-size: 0.8rem;
      line-height: 1.45;
      color: #9CA3AF;
    }
    .info-card strong {
      color: #F3F4F6;
    }

    /* Responsive adjustments */
    @media (max-width: 900px) {
      .preview-layout {
        flex-direction: column;
        align-items: center;
      }
      .inspector-panel {
        width: 100%;
        max-width: 400px;
      }
    }
  </style>
</head>
<body>

  <!-- Top Demo Control Header -->
  <header class="demo-bar">
    <div class="demo-title-group">
      <h1>
        Buildto Client Demonstration
        <span class="badge-demo">Interactive Prototype</span>
      </h1>
      <p>Source of truth: 16 Screens Specification &bull; Live Neon PostgreSQL Seeded &bull; Zero Flutter Build Required</p>
    </div>
    <div class="screen-selector-container">
      <select id="quickScreenSelect" class="screen-select" onchange="switchScreen(this.value)">
        <option value="s1">Screen 01: Home Screen</option>
        <option value="s2">Screen 02: Browse Category (Cement)</option>
        <option value="s3">Screen 03: Product Detail</option>
        <option value="s4">Screen 04: View Cart</option>
        <option value="s5">Screen 05: Checkout & Payment</option>
        <option value="s6">Screen 06: Order Placed</option>
        <option value="s7">Screen 07: Live Order Tracking</option>
        <option value="s8">Screen 08: My Orders</option>
        <option value="s9">Screen 09: Bulk Inquiry / RFQ</option>
        <option value="s10">Screen 10: Repeat Order</option>
        <option value="s11">Screen 11: Cancel Order</option>
        <option value="s12">Screen 12: Notifications</option>
        <option value="s13">Screen 13: Delivery Site Addresses</option>
        <option value="s14">Screen 14: Support & Dispatch Desk</option>
        <option value="s15">Screen 15: Construction Profile</option>
        <option value="s16">Screen 16: Saved Wishlist</option>
      </select>
    </div>
  </header>

  <!-- Main Preview Container -->
  <main class="preview-layout">

    <!-- Mobile Device Frame -->
    <div class="phone-frame">
      <div class="phone-notch"></div>
      <div class="phone-screen">

        <!-- Mobile Status Bar -->
        <div class="status-bar">
          <span>9:41</span>
          <div style="display: flex; gap: 6px; align-items: center;">
            <svg width="14" height="10" viewBox="0 0 14 10" fill="currentColor"><path d="M1 9h2V5H1v4zm4 0h2V3H5v6zm4 0h2V1H9v8zm4 0h2V0h-2v9z"/></svg>
            <svg width="14" height="10" viewBox="0 0 16 12" fill="currentColor"><path d="M8 0C4.9 0 2.2 1.3.4 3.4L8 12.8 15.6 3.4C13.8 1.3 11.1 0 8 0zm0 2.5c2.2 0 4.2.9 5.7 2.4L8 11.4 2.3 4.9C3.8 3.4 5.8 2.5 8 2.5z"/></svg>
            <svg width="18" height="10" viewBox="0 0 24 12" fill="currentColor"><rect x="1" y="1" width="19" height="10" rx="3" fill="none" stroke="currentColor" stroke-width="2"/><rect x="3" y="3" width="13" height="6" rx="1"/><path d="M21 4h1a1 1 0 0 1 1 1v2a1 1 0 0 1-1 1h-1V4z"/></svg>
          </div>
        </div>

        <!-- Viewport for 16 Screens -->
        <div class="screen-viewport" id="screenViewport">

          <!-- SCREEN 01: HOME SCREEN -->
          <div class="app-screen active" id="screen-s1">
            <div class="app-header">
              <div class="header-logo-group">
                <div class="logo-icon-box">B</div>
                <div>
                  <div class="header-brand">BUILDTO</div>
                  <div class="header-tagline">CONSTRUCTION MATERIALS MARKETPLACE</div>
                </div>
              </div>
              <div class="header-actions">
                <button class="header-btn" onclick="switchScreen('s12')" title="Notifications">
                  <svg viewBox="0 0 24 24"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"></path><path d="M13.73 21a2 2 0 0 1-3.46 0"></path></svg>
                  <span class="header-btn-badge"></span>
                </button>
                <button class="header-btn" onclick="switchScreen('s15')" title="Profile">
                  <svg viewBox="0 0 24 24"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path><circle cx="12" cy="7" r="4"></circle></svg>
                </button>
              </div>
            </div>

            <!-- Location Chip -->
            <div style="padding: 8px 16px; background: #EEF2F6; display: flex; align-items: center; justify-content: space-between; font-size: 0.75rem;">
              <div style="display: flex; align-items: center; gap: 6px; color: var(--primary); font-weight: 700;">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path><circle cx="12" cy="10" r="3"></circle></svg>
                <span>Site 1: Kabir Infra, Plot 42, Sector 62</span>
              </div>
              <span style="color: var(--secondary-hover); font-weight: 700; cursor: pointer;" onclick="switchScreen('s13')">Change</span>
            </div>

            <!-- Search Bar -->
            <div class="search-box">
              <svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line></svg>
              <input type="text" placeholder="Search cement, steel, bricks, sand..." onfocus="switchScreen('s2')">
            </div>

            <!-- Hero Banner -->
            <div class="hero-banner" onclick="switchScreen('s2')">
              <img src="assets/images/construction_hero_banner.jpg" alt="Construction Banner" onerror="this.src='https://images.unsplash.com/photo-1541888946425-d0fbb18615f8?w=800&auto=format&fit=crop&q=80'">
              <div class="hero-banner-overlay">
                <span class="hero-banner-tag">Wholesale Supply</span>
                <div class="hero-banner-title">Direct From Verified Mills & Plants</div>
                <div class="hero-banner-sub">Same-day site delivery &bull; Certified test reports</div>
              </div>
            </div>

            <!-- Nearby Suppliers -->
            <div class="section-head">
              <span class="section-title">Verified Nearby Suppliers</span>
              <span class="section-link">View All (6)</span>
            </div>
            <div class="supplier-scroll">
              <div class="supplier-card" onclick="switchScreen('s2')">
                <span class="sup-badge">&#10003; Verified Depot</span>
                <div class="sup-name">UltraTech Building Solutions</div>
                <div class="sup-meta">
                  <span>3.2 km away</span>
                  <span>&bull;</span>
                  <span style="color: var(--success); font-weight: 700;">Open &bull; Fast Dispatch</span>
                </div>
              </div>
              <div class="supplier-card" onclick="switchScreen('s2')">
                <span class="sup-badge">&#10003; Authorized Dealer</span>
                <div class="sup-name">Tata Tiscon Steel Yard</div>
                <div class="sup-meta">
                  <span>4.8 km away</span>
                  <span>&bull;</span>
                  <span style="color: var(--success); font-weight: 700;">Open &bull; Crane Loading</span>
                </div>
              </div>
              <div class="supplier-card" onclick="switchScreen('s2')">
                <span class="sup-badge">&#10003; Kiln Direct</span>
                <div class="sup-name">National Bricks & Aggregates</div>
                <div class="sup-meta">
                  <span>6.1 km away</span>
                  <span>&bull;</span>
                  <span style="color: var(--success); font-weight: 700;">Open &bull; Tipper Trucks</span>
                </div>
              </div>
            </div>

            <!-- Popular Categories -->
            <div class="section-head">
              <span class="section-title">Popular Categories</span>
              <span class="section-link" onclick="switchScreen('s2')">View All (9)</span>
            </div>
            <div class="category-strip">
              <div class="cat-pill" onclick="switchScreen('s2')">
                <div class="cat-pill-icon"><img src="assets/images/ultratech_cement.jpg" alt="Cement"></div>
                <span class="cat-pill-label">Cement</span>
              </div>
              <div class="cat-pill" onclick="switchScreen('s2')">
                <div class="cat-pill-icon"><img src="assets/images/tmt_steel_bars.jpg" alt="Steel"></div>
                <span class="cat-pill-label">Steel TMT</span>
              </div>
              <div class="cat-pill" onclick="switchScreen('s2')">
                <div class="cat-pill-icon"><img src="assets/images/red_bricks.jpg" alt="Bricks"></div>
                <span class="cat-pill-label">Bricks</span>
              </div>
              <div class="cat-pill" onclick="switchScreen('s2')">
                <div class="cat-pill-icon"><img src="assets/images/sand_aggregates.jpg" alt="Aggregates"></div>
                <span class="cat-pill-label">Sand & Agg</span>
              </div>
            </div>

            <!-- Featured Materials Grid -->
            <div class="section-head">
              <span class="section-title">High Demand Materials</span>
              <span class="section-link" onclick="switchScreen('s2')">See More</span>
            </div>
            <div class="product-grid" id="homeProductGrid">
              <!-- Rendered via JS -->
            </div>

            <!-- Quick RFQ Banner -->
            <div style="margin: 8px 16px 20px; background: linear-gradient(135deg, #002B5B 0%, #0A3D78 100%); border-radius: 14px; padding: 16px; color: white; display: flex; align-items: center; justify-content: space-between;">
              <div>
                <div style="font-size: 0.9rem; font-weight: 800;">Buying for large project?</div>
                <div style="font-size: 0.72rem; color: #CBD5E1; margin-top: 2px;">Submit RFQ for wholesale project pricing</div>
              </div>
              <button onclick="switchScreen('s9')" style="background: var(--secondary); color: #000; border: none; border-radius: 8px; padding: 8px 12px; font-size: 0.75rem; font-weight: 800; cursor: pointer;">
                Request Quote
              </button>
            </div>
          </div>

          <!-- SCREEN 02: BROWSE CATEGORY -->
          <div class="app-screen" id="screen-s2">
            <div class="nav-header">
              <button class="back-btn" onclick="switchScreen('s1')">
                <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
              </button>
              <span class="nav-header-title">Cement & Concrete</span>
              <button class="back-btn" onclick="switchScreen('s4')" title="Cart">
                <svg viewBox="0 0 24 24"><path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><line x1="3" y1="6" x2="21" y2="6"/><path d="M16 10a4 4 0 0 1-8 0"/></svg>
              </button>
            </div>

            <!-- Search inside category -->
            <div class="search-box" style="margin: 10px 16px;">
              <svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line></svg>
              <input type="text" placeholder="Search UltraTech, ACC, Ambuja...">
            </div>

            <!-- Filter Chips -->
            <div class="filter-chips">
              <span class="chip active" onclick="filterCategory(this, 'all')">All Cement</span>
              <span class="chip" onclick="filterCategory(this, 'opc')">OPC 53 Grade</span>
              <span class="chip" onclick="filterCategory(this, 'ppc')">PPC Weather Proof</span>
              <span class="chip" onclick="filterCategory(this, 'rmc')">Ready Mix (RMC)</span>
            </div>

            <!-- Category Product Grid -->
            <div class="product-grid" id="categoryProductGrid" style="margin-top: 14px;">
              <!-- Rendered via JS -->
            </div>
          </div>

          <!-- SCREEN 03: PRODUCT DETAIL -->
          <div class="app-screen" id="screen-s3">
            <div class="nav-header">
              <button class="back-btn" onclick="switchScreen('s2')">
                <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
              </button>
              <span class="nav-header-title">Material Details</span>
              <button class="back-btn" onclick="toggleWishlistCurrent()" id="btnWishlistHeader">
                <svg viewBox="0 0 24 24"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"></path></svg>
              </button>
            </div>

            <div class="detail-img-box">
              <img id="detailImg" src="assets/images/ultratech_cement.jpg" alt="Product Image">
              <span class="prod-tag" style="top: 14px; left: 14px; font-size: 0.7rem; padding: 4px 8px;">IS 269 Certified</span>
            </div>

            <div class="detail-body">
              <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                <div>
                  <span id="detailSupplier" style="font-size: 0.75rem; color: var(--text-muted); font-weight: 700;">UltraTech Building Solutions</span>
                  <h2 id="detailTitle" style="font-size: 1.15rem; font-weight: 800; color: var(--primary); margin: 4px 0 6px;">UltraTech Super OPC 53 Grade</h2>
                </div>
                <div style="text-align: right;">
                  <div id="detailPrice" style="font-size: 1.25rem; font-weight: 800; color: var(--primary);">&#8377;385</div>
                  <div id="detailUnit" style="font-size: 0.72rem; color: var(--text-muted);">per 50 kg bag</div>
                </div>
              </div>

              <!-- Specs Grid -->
              <div class="specs-grid">
                <div class="spec-item">
                  <div class="spec-label">Grade / Standard</div>
                  <div class="spec-value" id="detailGrade">OPC 53 Grade</div>
                </div>
                <div class="spec-item">
                  <div class="spec-label">Package Weight</div>
                  <div class="spec-value">50 kg HDPE Bag</div>
                </div>
                <div class="spec-item">
                  <div class="spec-label">Min Order Qty (MOQ)</div>
                  <div class="spec-value">25 Bags</div>
                </div>
                <div class="spec-item">
                  <div class="spec-label">Delivery Estimate</div>
                  <div class="spec-value" style="color: var(--success);">Same Day (Within 4 hrs)</div>
                </div>
              </div>

              <!-- Quantity Selector & Add CTA -->
              <div style="background: #F8FAFC; border: 1px solid var(--border); border-radius: 12px; padding: 12px; margin-bottom: 16px;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
                  <span style="font-size: 0.8rem; font-weight: 700; color: var(--text-main);">Select Quantity (Bags):</span>
                  <div style="display: flex; align-items: center; gap: 8px;">
                    <button class="qty-btn" onclick="updateDetailQty(-5)">-</button>
                    <span id="detailQty" style="font-size: 0.95rem; font-weight: 800; min-width: 30px; text-align: center;">25</span>
                    <button class="qty-btn" onclick="updateDetailQty(5)">+</button>
                  </div>
                </div>
                <div style="font-size: 0.7rem; color: var(--text-muted);">Total weight: <span id="detailWeight" style="font-weight: 700;">1,250 kg (1.25 Ton)</span></div>
              </div>

              <!-- Add to Cart CTA -->
              <button class="btn-primary-cta" style="width: 100%;" onclick="addCurrentDetailToCart()">
                <span>Add To Site Cart</span>
                <span id="detailTotalPrice">&#8377;9,625 &rarr;</span>
              </button>
            </div>
          </div>

          <!-- SCREEN 04: VIEW CART -->
          <div class="app-screen" id="screen-s4">
            <div class="nav-header">
              <button class="back-btn" onclick="switchScreen('s1')">
                <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
              </button>
              <span class="nav-header-title">My Cart (<span id="cartCountBadge">0</span>)</span>
              <button style="background: none; border: none; font-size: 0.75rem; font-weight: 700; color: var(--danger); cursor: pointer;" onclick="clearCart()">
                Clear
              </button>
            </div>

            <!-- Cart Items List -->
            <div id="cartItemsContainer" style="flex: 1; overflow-y: auto;">
              <!-- Dynamic cart items rendered here -->
            </div>

            <!-- Cart Summary & Checkout -->
            <div style="background: var(--surface); border-top: 1px solid var(--border); padding: 14px 16px;">
              <div class="cart-bill-box" style="margin: 0 0 14px;">
                <div class="bill-row">
                  <span>Materials Subtotal</span>
                  <span id="billSubtotal">&#8377;0</span>
                </div>
                <div class="bill-row">
                  <span>Site Delivery & Unloading</span>
                  <span id="billDelivery">&#8377;0</span>
                </div>
                <div class="bill-row">
                  <span>GST (18% / 28%)</span>
                  <span id="billGst">&#8377;0</span>
                </div>
                <div class="bill-row total">
                  <span>Grand Total</span>
                  <span id="billGrandTotal" style="color: var(--primary); font-size: 1.05rem;">&#8377;0</span>
                </div>
              </div>

              <button class="btn-primary-cta" style="width: 100%;" onclick="switchScreen('s5')" id="btnCheckout">
                <span>Proceed to Checkout</span>
                <span id="btnCheckoutTotal">&#8377;0 &rarr;</span>
              </button>
            </div>
          </div>

          <!-- SCREEN 05: CHECKOUT -->
          <div class="app-screen" id="screen-s5">
            <div class="nav-header">
              <button class="back-btn" onclick="switchScreen('s4')">
                <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
              </button>
              <span class="nav-header-title">Secure Checkout</span>
              <div style="width: 34px;"></div>
            </div>

            <div style="padding: 16px; flex: 1; overflow-y: auto;">
              <!-- Step Progress -->
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px; padding: 0 10px;">
                <div style="display: flex; align-items: center; gap: 6px; font-size: 0.75rem; font-weight: 800; color: var(--primary);">
                  <span style="width: 20px; height: 20px; border-radius: 50%; background: var(--primary); color: white; display: flex; align-items: center; justify-content: center; font-size: 0.65rem;">1</span>
                  Address
                </div>
                <div style="flex: 1; height: 2px; background: var(--primary); margin: 0 8px;"></div>
                <div style="display: flex; align-items: center; gap: 6px; font-size: 0.75rem; font-weight: 800; color: var(--primary);">
                  <span style="width: 20px; height: 20px; border-radius: 50%; background: var(--primary); color: white; display: flex; align-items: center; justify-content: center; font-size: 0.65rem;">2</span>
                  Payment
                </div>
                <div style="flex: 1; height: 2px; background: #CBD5E1; margin: 0 8px;"></div>
                <div style="display: flex; align-items: center; gap: 6px; font-size: 0.75rem; font-weight: 800; color: #94A3B8;">
                  <span style="width: 20px; height: 20px; border-radius: 50%; background: #CBD5E1; color: white; display: flex; align-items: center; justify-content: center; font-size: 0.65rem;">3</span>
                  Review
                </div>
              </div>

              <!-- Delivery Site Address Card -->
              <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 12px; margin-bottom: 14px;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
                  <span style="font-size: 0.8rem; font-weight: 800; color: var(--primary);">Delivery Site</span>
                  <span style="font-size: 0.7rem; font-weight: 700; color: var(--secondary-hover); cursor: pointer;" onclick="switchScreen('s13')">Change</span>
                </div>
                <div style="font-size: 0.8rem; font-weight: 700; color: var(--text-main);">Kabir Infra Projects &bull; Site 1</div>
                <div style="font-size: 0.72rem; color: var(--text-muted); margin-top: 2px;">Plot 42, Knowledge Park III, Greater Noida, UP - 201306</div>
                <div style="font-size: 0.7rem; color: #0284C7; margin-top: 6px; font-weight: 600;">Site Contact: Ramesh (Supervisor) +91 98765 43210</div>
              </div>

              <!-- Delivery Slot -->
              <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 12px; margin-bottom: 14px;">
                <span style="font-size: 0.8rem; font-weight: 800; color: var(--primary); display: block; margin-bottom: 8px;">Select Delivery Slot</span>
                <label style="display: flex; align-items: center; gap: 8px; font-size: 0.75rem; margin-bottom: 6px; cursor: pointer;">
                  <input type="radio" name="slot" checked>
                  <span><strong>Express Site Delivery:</strong> Today within 4 hours (Heavy Truck)</span>
                </label>
                <label style="display: flex; align-items: center; gap: 8px; font-size: 0.75rem; cursor: pointer;">
                  <input type="radio" name="slot">
                  <span><strong>Scheduled:</strong> Tomorrow 8:00 AM - 12:00 PM</span>
                </label>
              </div>

              <!-- Payment Method Selection -->
              <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 12px; margin-bottom: 14px;">
                <span style="font-size: 0.8rem; font-weight: 800; color: var(--primary); display: block; margin-bottom: 8px;">Select Payment Method</span>
                <div style="display: flex; flex-direction: column; gap: 8px;">
                  <label style="display: flex; align-items: center; gap: 10px; padding: 8px 10px; border: 1px solid var(--primary); border-radius: 8px; background: #F8FAFC; cursor: pointer;">
                    <input type="radio" name="paymentMethod" value="upi" checked>
                    <span style="font-size: 0.8rem; font-weight: 700;">UPI / Instant Bank Transfer (NEFT/RTGS)</span>
                  </label>
                  <label style="display: flex; align-items: center; gap: 10px; padding: 8px 10px; border: 1px solid var(--border); border-radius: 8px; cursor: pointer;">
                    <input type="radio" name="paymentMethod" value="cod">
                    <span style="font-size: 0.8rem; font-weight: 700;">Cash on Site Delivery (Pay to Truck Driver)</span>
                  </label>
                  <label style="display: flex; align-items: center; gap: 10px; padding: 8px 10px; border: 1px solid var(--border); border-radius: 8px; cursor: pointer;">
                    <input type="radio" name="paymentMethod" value="credit">
                    <span style="font-size: 0.8rem; font-weight: 700;">Commercial Builder Credit Line (30 Days)</span>
                  </label>
                </div>
              </div>

              <!-- Demo Notice -->
              <div style="background: #FEF3C7; border: 1px solid #FDE68A; border-radius: 10px; padding: 10px; font-size: 0.72rem; color: #92400E; margin-bottom: 16px;">
                <strong>Client Demo Notice:</strong> Simulated checkout creates a dynamic tracked order with unique Order ID and updates live order management without charging real funds.
              </div>

              <!-- Place Order Button -->
              <button class="btn-primary-cta" style="width: 100%;" onclick="placeSimulatedOrder()">
                <span>Confirm & Place Demo Order</span>
                <span id="checkoutFinalAmount">&#8377;9,625 &rarr;</span>
              </button>
            </div>
          </div>

          <!-- SCREEN 06: ORDER PLACED -->
          <div class="app-screen" id="screen-s6">
            <div class="success-container">
              <div class="success-circle">
                <svg width="44" height="44" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3"><polyline points="20 6 9 17 4 12"></polyline></svg>
              </div>
              <h2 style="font-size: 1.25rem; font-weight: 800; color: var(--primary);">Material Order Placed!</h2>
              <p style="font-size: 0.8rem; color: var(--text-muted); margin-top: 4px; max-width: 260px;">
                Depot has acknowledged the order. Loading & site dispatch will begin shortly.
              </p>

              <div class="order-id-badge" id="placedOrderIdBadge">Order ID: #BT012457</div>

              <div style="width: 100%; background: var(--surface); border: 1px solid var(--border); border-radius: 14px; padding: 14px; margin-bottom: 20px; text-align: left;">
                <div style="display: flex; justify-content: space-between; font-size: 0.75rem; margin-bottom: 6px;">
                  <span style="color: var(--text-muted);">Estimated Delivery:</span>
                  <span style="font-weight: 800; color: var(--primary);">Today by 4:00 PM</span>
                </div>
                <div style="display: flex; justify-content: space-between; font-size: 0.75rem; margin-bottom: 6px;">
                  <span style="color: var(--text-muted);">Delivery Site:</span>
                  <span style="font-weight: 700;">Plot 42, Sector 62</span>
                </div>
                <div style="display: flex; justify-content: space-between; font-size: 0.75rem;">
                  <span style="color: var(--text-muted);">Payment Status:</span>
                  <span style="color: var(--success); font-weight: 800;">Demo Verified</span>
                </div>
              </div>

              <button class="btn-primary-cta" style="width: 100%; margin-bottom: 10px;" onclick="trackCurrentPlacedOrder()">
                <span>Track Live Order</span>
                <span>&rarr;</span>
              </button>

              <button style="background: transparent; border: 1px solid var(--border); border-radius: 12px; padding: 12px; font-size: 0.8rem; font-weight: 700; color: var(--primary); width: 100%; cursor: pointer;" onclick="switchScreen('s1')">
                Continue Shopping
              </button>
            </div>
          </div>

          <!-- SCREEN 07: TRACK ORDER -->
          <div class="app-screen" id="screen-s7">
            <div class="nav-header">
              <button class="back-btn" onclick="switchScreen('s8')">
                <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
              </button>
              <span class="nav-header-title">Live Dispatch Tracking</span>
              <div style="width: 34px;"></div>
            </div>

            <div style="padding: 14px 16px; flex: 1; overflow-y: auto;">
              <!-- Order Header Card -->
              <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 14px; padding: 12px; margin-bottom: 14px; display: flex; justify-content: space-between; align-items: center;">
                <div>
                  <div id="trackOrderId" style="font-size: 0.95rem; font-weight: 800; color: var(--primary);">#BT012457</div>
                  <div style="font-size: 0.7rem; color: var(--text-muted);" id="trackOrderDate">Placed Today, 9:42 AM</div>
                </div>
                <span id="trackStatusBadge" style="background: #ECFDF5; color: #065F46; font-size: 0.7rem; font-weight: 800; padding: 4px 10px; border-radius: 20px;">
                  In Transit
                </span>
              </div>

              <!-- Truck Illustration Banner -->
              <div style="border-radius: 14px; overflow: hidden; height: 120px; background: #0F172A; margin-bottom: 14px; position: relative;">
                <img src="assets/images/delivery_truck_illustration.jpg" alt="Delivery Truck" style="width: 100%; height: 100%; object-fit: cover; opacity: 0.85;">
                <div style="position: absolute; inset: 0; background: linear-gradient(180deg, rgba(0,0,0,0.1), rgba(0,0,0,0.7)); display: flex; align-items: flex-end; padding: 10px 14px; color: white;">
                  <div>
                    <div style="font-size: 0.8rem; font-weight: 800;">Heavy Tipper Truck: UP 16 BT 4421</div>
                    <div style="font-size: 0.68rem; color: #CBD5E1;">Driver: Rajesh Kumar &bull; Arriving in ~35 mins</div>
                  </div>
                </div>
              </div>

              <!-- Live Timeline -->
              <div class="tracking-timeline">
                <div class="timeline-step completed">
                  <div class="timeline-icon">&#10003;</div>
                  <div>
                    <div style="font-size: 0.8rem; font-weight: 700; color: var(--primary);">Order Received & Verified</div>
                    <div style="font-size: 0.68rem; color: var(--text-muted);">Depot manager accepted material allocation</div>
                  </div>
                </div>
                <div class="timeline-step completed">
                  <div class="timeline-icon">&#10003;</div>
                  <div>
                    <div style="font-size: 0.8rem; font-weight: 700; color: var(--primary);">Material Loaded & Weighbridge Weighed</div>
                    <div style="font-size: 0.68rem; color: var(--text-muted);">Gross weight verified against challan #CH-8841</div>
                  </div>
                </div>
                <div class="timeline-step active">
                  <div class="timeline-icon">&bull;</div>
                  <div>
                    <div style="font-size: 0.8rem; font-weight: 700; color: var(--secondary-hover);">Out for Site Delivery</div>
                    <div style="font-size: 0.68rem; color: var(--text-muted);">Truck en route to Sector 62 via Expressway</div>
                  </div>
                </div>
                <div class="timeline-step">
                  <div class="timeline-icon">4</div>
                  <div>
                    <div style="font-size: 0.8rem; font-weight: 700; color: #94A3B8;">Unloaded at Project Site</div>
                    <div style="font-size: 0.68rem; color: var(--text-muted);">Pending site supervisor signature</div>
                  </div>
                </div>
              </div>

              <!-- Dynamic Items in this order -->
              <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 14px; padding: 12px; margin-bottom: 14px;">
                <span style="font-size: 0.8rem; font-weight: 800; color: var(--primary); display: block; margin-bottom: 8px;">Order Manifest</span>
                <div id="trackItemsManifest">
                  <!-- Dynamically inserted -->
                </div>
              </div>

              <!-- Action buttons -->
              <div style="display: flex; gap: 10px;">
                <button onclick="switchScreen('s14')" style="flex: 1; background: #F1F5F9; border: 1px solid var(--border); border-radius: 10px; padding: 10px; font-size: 0.75rem; font-weight: 700; color: var(--primary); cursor: pointer;">
                  Contact Dispatch Desk
                </button>
                <button onclick="promptCancelCurrentOrder()" style="flex: 1; background: #FEF2F2; border: 1px solid #FECACA; border-radius: 10px; padding: 10px; font-size: 0.75rem; font-weight: 700; color: var(--danger); cursor: pointer;">
                  Cancel Material Order
                </button>
              </div>
            </div>
          </div>

          <!-- SCREEN 08: MY ORDERS -->
          <div class="app-screen" id="screen-s8">
            <div class="nav-header">
              <button class="back-btn" onclick="switchScreen('s1')">
                <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
              </button>
              <span class="nav-header-title">My Orders</span>
              <div style="width: 34px;"></div>
            </div>

            <!-- Order Tabs -->
            <div class="filter-chips">
              <span class="chip active" onclick="filterOrderTab(this, 'all')">All (3)</span>
              <span class="chip" onclick="filterOrderTab(this, 'processing')">Processing</span>
              <span class="chip" onclick="filterOrderTab(this, 'delivered')">Delivered</span>
              <span class="chip" onclick="filterOrderTab(this, 'cancelled')">Cancelled</span>
            </div>

            <div id="ordersListContainer" style="padding: 12px 16px; flex: 1; overflow-y: auto;">
              <!-- Dynamic orders rendered here -->
            </div>
          </div>

          <!-- SCREEN 09: BULK INQUIRY / RFQ -->
          <div class="app-screen" id="screen-s9">
            <div class="nav-header">
              <button class="back-btn" onclick="switchScreen('s1')">
                <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
              </button>
              <span class="nav-header-title">Bulk Project RFQ</span>
              <div style="width: 34px;"></div>
            </div>

            <div style="padding: 16px; flex: 1; overflow-y: auto;">
              <div style="background: linear-gradient(135deg, #002B5B 0%, #0A3D78 100%); color: white; border-radius: 14px; padding: 14px; margin-bottom: 16px;">
                <div style="font-size: 0.95rem; font-weight: 800;">Institutional Builder Pricing</div>
                <div style="font-size: 0.72rem; color: #CBD5E1; margin-top: 4px;">Get plant-direct quotations for trailer/truckload volumes (>10 tons or 500 bags).</div>
              </div>

              <div style="display: flex; flex-direction: column; gap: 12px;">
                <div>
                  <label style="font-size: 0.75rem; font-weight: 700; color: var(--text-main); display: block; margin-bottom: 4px;">Material Requirement</label>
                  <select style="width: 100%; padding: 10px; border-radius: 8px; border: 1px solid var(--border); font-size: 0.8rem;">
                    <option>UltraTech Super OPC 53 Grade Cement</option>
                    <option>Tata Tiscon 550D TMT Steel (12mm & 16mm)</option>
                    <option>First Class Red Clay Bricks (Wire Cut)</option>
                    <option>River Sand & 20mm Blue Metal Aggregates</option>
                  </select>
                </div>

                <div>
                  <label style="font-size: 0.75rem; font-weight: 700; color: var(--text-main); display: block; margin-bottom: 4px;">Expected Quantity</label>
                  <input type="text" value="500 Bags (25 Metric Tons)" style="width: 100%; padding: 10px; border-radius: 8px; border: 1px solid var(--border); font-size: 0.8rem;">
                </div>

                <div>
                  <label style="font-size: 0.75rem; font-weight: 700; color: var(--text-main); display: block; margin-bottom: 4px;">Delivery Project Site</label>
                  <input type="text" value="Kabir Infra Tower, Plot 42, Greater Noida" style="width: 100%; padding: 10px; border-radius: 8px; border: 1px solid var(--border); font-size: 0.8rem;">
                </div>

                <div>
                  <label style="font-size: 0.75rem; font-weight: 700; color: var(--text-main); display: block; margin-bottom: 4px;">Required by Date</label>
                  <input type="date" value="2026-10-28" style="width: 100%; padding: 10px; border-radius: 8px; border: 1px solid var(--border); font-size: 0.8rem;">
                </div>

                <div>
                  <label style="font-size: 0.75rem; font-weight: 700; color: var(--text-main); display: block; margin-bottom: 4px;">Special Site Instructions (Optional)</label>
                  <textarea placeholder="e.g. Crane unloader required, narrow approach road..." style="width: 100%; height: 70px; padding: 10px; border-radius: 8px; border: 1px solid var(--border); font-size: 0.8rem;"></textarea>
                </div>

                <button class="btn-primary-cta" style="margin-top: 10px;" onclick="submitRfqDemo()">
                  <span>Submit RFQ to Plant Sales</span>
                  <span>&rarr;</span>
                </button>
              </div>
            </div>
          </div>

          <!-- SCREEN 10: REPEAT ORDER -->
          <div class="app-screen" id="screen-s10">
            <div class="nav-header">
              <button class="back-btn" onclick="switchScreen('s1')">
                <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
              </button>
              <span class="nav-header-title">Quick Repeat Order</span>
              <div style="width: 34px;"></div>
            </div>

            <div style="padding: 14px 16px; flex: 1; overflow-y: auto;">
              <p style="font-size: 0.78rem; color: var(--text-muted); margin-bottom: 14px;">
                Reorder materials frequently used on your active sites with 1-click quantity re-adds.
              </p>

              <div id="repeatOrdersContainer">
                <!-- Populated via JS -->
              </div>
            </div>
          </div>

          <!-- SCREEN 11: CANCEL ORDER -->
          <div class="app-screen" id="screen-s11">
            <div class="nav-header">
              <button class="back-btn" onclick="switchScreen('s7')">
                <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
              </button>
              <span class="nav-header-title">Cancel Material Order</span>
              <div style="width: 34px;"></div>
            </div>

            <div style="padding: 16px; flex: 1; overflow-y: auto;">
              <div style="background: #FEF2F2; border: 1px solid #FECACA; border-radius: 12px; padding: 12px; margin-bottom: 16px;">
                <div style="font-size: 0.85rem; font-weight: 800; color: var(--danger);">Are you sure you want to cancel?</div>
                <div style="font-size: 0.72rem; color: #991B1B; margin-top: 2px;">
                  Cancelling will alert the depot dispatch desk immediately. Once a tipper truck departs depot, unloading charges may apply.
                </div>
              </div>

              <div style="font-size: 0.8rem; font-weight: 800; color: var(--primary); margin-bottom: 8px;">Select Reason for Cancellation:</div>
              <div style="display: flex; flex-direction: column; gap: 8px; margin-bottom: 20px;">
                <label style="display: flex; align-items: center; gap: 8px; font-size: 0.75rem; cursor: pointer; padding: 8px; border: 1px solid var(--border); border-radius: 8px;">
                  <input type="radio" name="cancelReason" checked value="Concrete pouring delayed due to rain">
                  <span>Concrete pouring delayed due to rain / weather</span>
                </label>
                <label style="display: flex; align-items: center; gap: 8px; font-size: 0.75rem; cursor: pointer; padding: 8px; border: 1px solid var(--border); border-radius: 8px;">
                  <input type="radio" name="cancelReason" value="Ordered incorrect grade or specification">
                  <span>Ordered incorrect grade or specification</span>
                </label>
                <label style="display: flex; align-items: center; gap: 8px; font-size: 0.75rem; cursor: pointer; padding: 8px; border: 1px solid var(--border); border-radius: 8px;">
                  <input type="radio" name="cancelReason" value="Material procured locally on emergency basis">
                  <span>Material procured locally on emergency basis</span>
                </label>
                <label style="display: flex; align-items: center; gap: 8px; font-size: 0.75rem; cursor: pointer; padding: 8px; border: 1px solid var(--border); border-radius: 8px;">
                  <input type="radio" name="cancelReason" value="Duplicate demo test order placed">
                  <span>Duplicate demo test order placed</span>
                </label>
              </div>

              <button class="btn-primary-cta" style="background: var(--danger); width: 100%; margin-bottom: 10px;" onclick="confirmCancelOrder()">
                <span>Confirm Order Cancellation</span>
                <span>&rarr;</span>
              </button>

              <button style="background: transparent; border: 1px solid var(--border); border-radius: 12px; padding: 12px; font-size: 0.8rem; font-weight: 700; color: var(--primary); width: 100%; cursor: pointer;" onclick="switchScreen('s7')">
                Keep Order Active
              </button>
            </div>
          </div>

          <!-- SCREEN 12: NOTIFICATIONS -->
          <div class="app-screen" id="screen-s12">
            <div class="nav-header">
              <button class="back-btn" onclick="switchScreen('s1')">
                <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
              </button>
              <span class="nav-header-title">Notifications</span>
              <button style="background: none; border: none; font-size: 0.75rem; font-weight: 700; color: var(--primary); cursor: pointer;" onclick="markAllNotificationsRead()">
                Read All
              </button>
            </div>

            <div style="padding: 12px 16px; flex: 1; overflow-y: auto;" id="notificationsContainer">
              <!-- Rendered via JS -->
            </div>
          </div>

          <!-- SCREEN 13: DELIVERY SITE ADDRESSES -->
          <div class="app-screen" id="screen-s13">
            <div class="nav-header">
              <button class="back-btn" onclick="switchScreen('s1')">
                <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
              </button>
              <span class="nav-header-title">Delivery Sites</span>
              <div style="width: 34px;"></div>
            </div>

            <div style="padding: 16px; flex: 1; overflow-y: auto;">
              <!-- Active Address 1 -->
              <div style="background: #F8FAFC; border: 2px solid var(--primary); border-radius: 12px; padding: 14px; margin-bottom: 12px; position: relative;">
                <span style="position: absolute; top: 12px; right: 12px; background: var(--primary); color: white; font-size: 0.65rem; font-weight: 800; padding: 2px 8px; border-radius: 12px;">ACTIVE SITE</span>
                <div style="font-size: 0.9rem; font-weight: 800; color: var(--primary);">Main Project Site (Tower A)</div>
                <div style="font-size: 0.75rem; color: var(--text-main); margin-top: 4px;">Plot 42, Knowledge Park III, Greater Noida, UP - 201306</div>
                <div style="font-size: 0.72rem; color: var(--text-muted); margin-top: 4px;">Supervisor: Ramesh Chandra (+91 98765 43210)</div>
              </div>

              <!-- Address 2 -->
              <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 14px; margin-bottom: 16px;">
                <div style="font-size: 0.9rem; font-weight: 800; color: var(--text-main);">Sector 150 Warehouse Yard</div>
                <div style="font-size: 0.75rem; color: var(--text-main); margin-top: 4px;">Shed 7, Transport Nagar, Noida Express Corridor</div>
                <div style="font-size: 0.72rem; color: var(--text-muted); margin-top: 4px;">Supervisor: Sunil Verma (+91 98112 34567)</div>
              </div>

              <!-- Add New Site CTA -->
              <button class="btn-primary-cta" style="width: 100%;" onclick="alert('Demo: Add Site Dialog opened. In production, this allows pinpointing GPS coordinates for heavy vehicle access.')">
                <span>+ Add New Project Site</span>
                <span>&rarr;</span>
              </button>
            </div>
          </div>

          <!-- SCREEN 14: SUPPORT & DISPATCH DESK -->
          <div class="app-screen" id="screen-s14">
            <div class="nav-header">
              <button class="back-btn" onclick="switchScreen('s1')">
                <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
              </button>
              <span class="nav-header-title">Support & Dispatch Desk</span>
              <div style="width: 34px;"></div>
            </div>

            <div style="padding: 16px; flex: 1; overflow-y: auto;">
              <!-- Hotline card -->
              <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 14px; padding: 16px; text-align: center; margin-bottom: 16px; box-shadow: var(--shadow-sm);">
                <div style="width: 50px; height: 50px; background: #EEF2F6; border-radius: 50%; display: flex; align-items: center; justify-content: center; margin: 0 auto 10px; color: var(--primary);">
                  <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"></path></svg>
                </div>
                <div style="font-size: 0.95rem; font-weight: 800; color: var(--primary);">Central Dispatch Control</div>
                <div style="font-size: 0.8rem; color: var(--text-muted); margin-top: 4px;">Direct line to regional yard master & weighbridge officers</div>
                <div style="font-size: 1.1rem; font-weight: 800; color: var(--secondary-hover); margin: 8px 0;">+91 98765 00123</div>
                <div style="font-size: 0.7rem; color: var(--success); font-weight: 700;">Operational: Mon - Sat (6:00 AM - 9:00 PM)</div>
              </div>

              <!-- FAQ & Assistance options -->
              <div style="display: flex; flex-direction: column; gap: 10px;">
                <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 12px; cursor: pointer;" onclick="alert('FAQ: Cement deliveries are backed by batch test certificates (IS 269/IS 1489).')">
                  <div style="font-size: 0.8rem; font-weight: 700; color: var(--primary);">Quality Test Certificates & MTC</div>
                  <div style="font-size: 0.7rem; color: var(--text-muted); margin-top: 2px;">Download Mill Test Certificates for structural approvals</div>
                </div>
                <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 12px; cursor: pointer;" onclick="alert('FAQ: Refunds for cancelled orders are processed according to standard banking cycles (3-5 business days).')">
                  <div style="font-size: 0.8rem; font-weight: 700; color: var(--primary);">Refund & Cancellation Policies</div>
                  <div style="font-size: 0.7rem; color: var(--text-muted); margin-top: 2px;">Standard 3-5 business days banking clearance for advance payments</div>
                </div>
                <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 12px; cursor: pointer;" onclick="alert('FAQ: Heavy trailers require min 20-foot approach road.')">
                  <div style="font-size: 0.8rem; font-weight: 700; color: var(--primary);">Heavy Vehicle Site Access Guidelines</div>
                  <div style="font-size: 0.7rem; color: var(--text-muted); margin-top: 2px;">Road clearance criteria for 10-tyre and 14-tyre tippers</div>
                </div>
              </div>
            </div>
          </div>

          <!-- SCREEN 15: CONSTRUCTION PROFILE -->
          <div class="app-screen" id="screen-s15">
            <div class="nav-header">
              <button class="back-btn" onclick="switchScreen('s1')">
                <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
              </button>
              <span class="nav-header-title">Contractor Profile</span>
              <div style="width: 34px;"></div>
            </div>

            <div style="padding: 16px; flex: 1; overflow-y: auto;">
              <!-- Profile Avatar & Details -->
              <div style="display: flex; align-items: center; gap: 14px; background: var(--surface); border: 1px solid var(--border); border-radius: 14px; padding: 16px; margin-bottom: 16px;">
                <img src="assets/images/construction_engineer.jpg" alt="Engineer Avatar" style="width: 60px; height: 60px; border-radius: 50%; object-fit: cover; border: 2px solid var(--secondary);">
                <div>
                  <div style="display: flex; align-items: center; gap: 6px;">
                    <span style="font-size: 1rem; font-weight: 800; color: var(--primary);">Mohd Kabir</span>
                    <span style="background: #ECFDF5; color: #065F46; font-size: 0.65rem; font-weight: 800; padding: 2px 6px; border-radius: 4px;">VERIFIED</span>
                  </div>
                  <div style="font-size: 0.75rem; color: var(--text-muted); margin-top: 2px;">Kabir Infra & Projects Ltd.</div>
                  <div style="font-size: 0.7rem; color: #0284C7; font-weight: 600;">GSTIN: 07AAAAA0000A1Z5</div>
                </div>
              </div>

              <!-- Quick action links -->
              <div style="display: flex; flex-direction: column; gap: 8px;">
                <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 12px; display: flex; justify-content: space-between; align-items: center; cursor: pointer;" onclick="switchScreen('s8')">
                  <span style="font-size: 0.8rem; font-weight: 700;">My Order History & Challans</span>
                  <span style="color: var(--text-muted);">&rarr;</span>
                </div>
                <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 12px; display: flex; justify-content: space-between; align-items: center; cursor: pointer;" onclick="switchScreen('s16')">
                  <span style="font-size: 0.8rem; font-weight: 700;">Saved Wishlist Materials</span>
                  <span style="color: var(--text-muted);">&rarr;</span>
                </div>
                <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 12px; display: flex; justify-content: space-between; align-items: center; cursor: pointer;" onclick="switchScreen('s13')">
                  <span style="font-size: 0.8rem; font-weight: 700;">Managed Site Addresses</span>
                  <span style="color: var(--text-muted);">&rarr;</span>
                </div>
                <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 12px; display: flex; justify-content: space-between; align-items: center; cursor: pointer;" onclick="switchScreen('s14')">
                  <span style="font-size: 0.8rem; font-weight: 700;">Dispatch Desk Helpline</span>
                  <span style="color: var(--text-muted);">&rarr;</span>
                </div>
              </div>
            </div>
          </div>

          <!-- SCREEN 16: WISHLIST -->
          <div class="app-screen" id="screen-s16">
            <div class="nav-header">
              <button class="back-btn" onclick="switchScreen('s1')">
                <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
              </button>
              <span class="nav-header-title">Saved Wishlist</span>
              <div style="width: 34px;"></div>
            </div>

            <div style="padding: 12px 16px; flex: 1; overflow-y: auto;" id="wishlistContainer">
              <!-- Rendered via JS -->
            </div>
          </div>

        </div>

        <!-- Bottom Navigation Bar (Persistent) -->
        <nav class="bottom-nav">
          <div class="nav-item active" onclick="switchNav('home', 's1')" id="nav-home">
            <svg viewBox="0 0 24 24"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path><polyline points="9 22 9 12 15 12 15 22"></polyline></svg>
            <span>Home</span>
          </div>
          <div class="nav-item" onclick="switchNav('categories', 's2')" id="nav-categories">
            <svg viewBox="0 0 24 24"><rect x="3" y="3" width="7" height="7"></rect><rect x="14" y="3" width="7" height="7"></rect><rect x="14" y="14" width="7" height="7"></rect><rect x="3" y="14" width="7" height="7"></rect></svg>
            <span>Categories</span>
          </div>
          <div class="nav-item" onclick="switchNav('cart', 's4')" id="nav-cart">
            <svg viewBox="0 0 24 24"><path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><line x1="3" y1="6" x2="21" y2="6"/><path d="M16 10a4 4 0 0 1-8 0"/></svg>
            <span class="nav-badge" id="bottomNavCartBadge">0</span>
            <span>Cart</span>
          </div>
          <div class="nav-item" onclick="switchNav('orders', 's8')" id="nav-orders">
            <svg viewBox="0 0 24 24"><line x1="16.5" y1="9.4" x2="7.5" y2="4.21"></line><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"></path><polyline points="3.27 6.96 12 12.01 20.73 6.96"></polyline><line x1="12" y1="22.08" x2="12" y2="12"></line></svg>
            <span>Orders</span>
          </div>
          <div class="nav-item" onclick="switchNav('profile', 's15')" id="nav-profile">
            <svg viewBox="0 0 24 24"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path><circle cx="12" cy="7" r="4"></circle></svg>
            <span>Profile</span>
          </div>
        </nav>

      </div>
    </div>

    <!-- Inspector & Screen Switcher Panel (Right Side for Desktop Presenter) -->
    <aside class="inspector-panel">
      <div class="inspector-title">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--secondary)" stroke-width="2.5"><rect x="2" y="3" width="20" height="14" rx="2" ry="2"></rect><line x1="8" y1="21" x2="16" y2="21"></line><line x1="12" y1="17" x2="12" y2="21"></line></svg>
        <span>16-Screen Navigation Grid</span>
      </div>

      <p style="font-size: 0.8rem; color: #9CA3AF;">
        Select any screen below during your client demo to demonstrate layout and functionality directly, or click through the interactive shopping flow inside the phone mockup.
      </p>

      <div class="screen-grid-nav">
        <button class="screen-btn active" onclick="switchScreen('s1')" id="sbtn-s1">
          <span class="screen-num">Screen 01</span>
          <span>Home Screen</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s2')" id="sbtn-s2">
          <span class="screen-num">Screen 02</span>
          <span>Browse Category</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s3')" id="sbtn-s3">
          <span class="screen-num">Screen 03</span>
          <span>Product Detail</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s4')" id="sbtn-s4">
          <span class="screen-num">Screen 04</span>
          <span>View Cart</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s5')" id="sbtn-s5">
          <span class="screen-num">Screen 05</span>
          <span>Checkout & Pay</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s6')" id="sbtn-s6">
          <span class="screen-num">Screen 06</span>
          <span>Order Placed</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s7')" id="sbtn-s7">
          <span class="screen-num">Screen 07</span>
          <span>Track Order</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s8')" id="sbtn-s8">
          <span class="screen-num">Screen 08</span>
          <span>My Orders</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s9')" id="sbtn-s9">
          <span class="screen-num">Screen 09</span>
          <span>Bulk RFQ</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s10')" id="sbtn-s10">
          <span class="screen-num">Screen 10</span>
          <span>Repeat Order</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s11')" id="sbtn-s11">
          <span class="screen-num">Screen 11</span>
          <span>Cancel Order</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s12')" id="sbtn-s12">
          <span class="screen-num">Screen 12</span>
          <span>Notifications</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s13')" id="sbtn-s13">
          <span class="screen-num">Screen 13</span>
          <span>Site Addresses</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s14')" id="sbtn-s14">
          <span class="screen-num">Screen 14</span>
          <span>Support & Help</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s15')" id="sbtn-s15">
          <span class="screen-num">Screen 15</span>
          <span>Profile</span>
        </button>
        <button class="screen-btn" onclick="switchScreen('s16')" id="sbtn-s16">
          <span class="screen-num">Screen 16</span>
          <span>Saved Wishlist</span>
        </button>
      </div>

      <div class="info-card">
        <strong>Database & State Note:</strong><br>
        Backend seed verified on Neon PostgreSQL with 9 categories, 6 suppliers & 54 construction SKUs. Dynamic cart, checkout order generator, dynamic cancellation, and order tracking operate live in this browser demo.
      </div>
    </aside>

  </main>

  <!-- Prototype Data & State Script -->
  <script>
    // Product Catalog (Mirrors Neon Seed & Local Sample Data)
    const PRODUCTS = [
      {
        id: 'p1',
        name: 'UltraTech Super OPC 53 Grade',
        category: 'cement',
        subType: 'opc',
        supplier: 'UltraTech Building Solutions',
        price: 385,
        unit: '50 kg bag',
        moq: 25,
        grade: 'OPC 53 Grade (IS 269)',
        image: 'assets/images/ultratech_cement.jpg',
        badge: 'High Strength',
        inStock: true
      },
      {
        id: 'p2',
        name: 'ACC Suraksha Power PPC Cement',
        category: 'cement',
        subType: 'ppc',
        supplier: 'ACC Concrete Depot',
        price: 370,
        unit: '50 kg bag',
        moq: 25,
        grade: 'PPC Weather Shield (IS 1489)',
        image: 'assets/images/acc_cement.jpg',
        badge: 'Weather Proof',
        inStock: true
      },
      {
        id: 'p3',
        name: 'Ambuja Kawach Waterproof Cement',
        category: 'cement',
        subType: 'ppc',
        supplier: 'Ambuja Authorized Yard',
        price: 395,
        unit: '50 kg bag',
        moq: 25,
        grade: 'Water Repellent PPC',
        image: 'assets/images/ambuja_cement.jpg',
        badge: 'Waterproof',
        inStock: true
      },
      {
        id: 'p4',
        name: 'Dalmia DSP High Performance Cement',
        category: 'cement',
        subType: 'opc',
        supplier: 'Dalmia Direct Depot',
        price: 375,
        unit: '50 kg bag',
        moq: 25,
        grade: 'Special Grade 53',
        image: 'assets/images/dalmia_cement.jpg',
        badge: 'Heavy Duty',
        inStock: true
      },
      {
        id: 'p5',
        name: 'Tata Tiscon 550D TMT Rebar (12mm)',
        category: 'steel',
        subType: 'tmt',
        supplier: 'Tata Tiscon Steel Yard',
        price: 68,
        unit: 'per kg',
        moq: 500,
        grade: 'Fe 550D Super Ductile',
        image: 'assets/images/tmt_steel_bars.jpg',
        badge: 'Primary Mill',
        inStock: true
      },
      {
        id: 'p6',
        name: 'First Class Red Kiln Bricks (Wire Cut)',
        category: 'bricks',
        subType: 'clay',
        supplier: 'National Bricks & Aggregates',
        price: 9,
        unit: 'per brick',
        moq: 1000,
        grade: 'Standard 9x4x3 inch',
        image: 'assets/images/red_bricks.jpg',
        badge: 'Kiln Baked',
        inStock: true
      },
      {
        id: 'p7',
        name: 'River Sand (Coarse Construction Grade)',
        category: 'sand',
        subType: 'sand',
        supplier: 'National Bricks & Aggregates',
        price: 48,
        unit: 'per cu.ft',
        moq: 100,
        grade: 'Zone II Washed',
        image: 'assets/images/sand_aggregates.jpg',
        badge: 'Washed Silt-free',
        inStock: true
      }
    ];

    // State Variables
    let cart = [
      { product: PRODUCTS[0], quantity: 25 } // Default initial sample
    ];
    let selectedProductForDetail = PRODUCTS[0];
    let detailSelectedQty = 25;
    let nextOrderCounter = 12457;

    let orders = [
      {
        id: '#BT012456',
        date: 'Yesterday, 3:30 PM',
        status: 'Delivered',
        statusClass: 'completed',
        items: [
          { name: 'Tata Tiscon 550D TMT Rebar (12mm)', qty: '500 kg', price: 34000 }
        ],
        total: 40120,
        site: 'Sector 150 Warehouse Yard'
      }
    ];

    let currentActiveOrder = null;

    let notifications = [
      { id: 1, title: 'Truck Out For Site Delivery', body: 'Tipper truck UP 16 BT 4421 has left UltraTech Depot. ETA 35 mins.', time: '10m ago', unread: true },
      { id: 2, title: 'Mill Test Certificate Ready', body: 'MTC for batch #UT-9921 is available for download in Order #BT012456.', time: '1h ago', unread: true },
      { id: 3, title: 'Cement Price Alert', body: 'Special builder rebate of \u20B915/bag available on orders over 100 bags.', time: '1d ago', unread: false }
    ];

    let wishlist = [ PRODUCTS[1], PRODUCTS[4] ];

    // Initialization
    function init() {
      renderHomeProducts();
      renderCategoryProducts(PRODUCTS);
      renderCart();
      renderOrders();
      renderNotifications();
      renderRepeatOrders();
      renderWishlist();
    }

    // Navigation Switcher
    function switchScreen(screenId) {
      document.querySelectorAll('.app-screen').forEach(s => s.classList.remove('active'));
      const target = document.getElementById('screen-' + screenId);
      if (target) {
        target.classList.add('active');
        document.getElementById('screenViewport').scrollTop = 0;
      }

      // Update Screen Grid Buttons in Inspector
      document.querySelectorAll('.screen-btn').forEach(btn => btn.classList.remove('active'));
      const activeBtn = document.getElementById('sbtn-' + screenId);
      if (activeBtn) activeBtn.classList.add('active');

      // Update Quick Select Dropdown
      const quickSelect = document.getElementById('quickScreenSelect');
      if (quickSelect) quickSelect.value = screenId;

      // Update Bottom Nav if applicable
      updateBottomNavForScreen(screenId);
    }

    function switchNav(navKey, screenId) {
      document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
      const navItem = document.getElementById('nav-' + navKey);
      if (navItem) navItem.classList.add('active');
      switchScreen(screenId);
    }

    function updateBottomNavForScreen(screenId) {
      document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
      if (screenId === 's1') document.getElementById('nav-home')?.classList.add('active');
      else if (screenId === 's2') document.getElementById('nav-categories')?.classList.add('active');
      else if (screenId === 's4') document.getElementById('nav-cart')?.classList.add('active');
      else if (screenId === 's8') document.getElementById('nav-orders')?.classList.add('active');
      else if (screenId === 's15') document.getElementById('nav-profile')?.classList.add('active');
    }

    // Render Home Products
    function renderHomeProducts() {
      const grid = document.getElementById('homeProductGrid');
      grid.innerHTML = PRODUCTS.slice(0, 4).map(p => `
        <div class="product-card" onclick="openProductDetail('${p.id}')">
          <div class="prod-img-box">
            <img src="${p.image}" alt="${p.name}" onerror="this.src='https://images.unsplash.com/photo-1541888946425-d0fbb18615f8?w=400'">
            <span class="prod-tag">${p.badge}</span>
            <button class="prod-wish" onclick="event.stopPropagation(); toggleWishlist('${p.id}')">
              <svg viewBox="0 0 24 24"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"></path></svg>
            </button>
          </div>
          <div class="prod-info">
            <div class="prod-supplier">${p.supplier}</div>
            <div class="prod-title">${p.name}</div>
            <div class="prod-price-row">
              <div class="prod-price">&#8377;${p.price}</div>
              <div class="prod-unit">${p.unit}</div>
            </div>
            <button class="btn-add-cart" onclick="event.stopPropagation(); quickAddToCart('${p.id}')">
              + Add to Cart
            </button>
          </div>
        </div>
      `).join('');
    }

    // Render Category Products
    function renderCategoryProducts(list) {
      const grid = document.getElementById('categoryProductGrid');
      grid.innerHTML = list.map(p => `
        <div class="product-card" onclick="openProductDetail('${p.id}')">
          <div class="prod-img-box">
            <img src="${p.image}" alt="${p.name}" onerror="this.src='https://images.unsplash.com/photo-1541888946425-d0fbb18615f8?w=400'">
            <span class="prod-tag">${p.badge}</span>
            <button class="prod-wish" onclick="event.stopPropagation(); toggleWishlist('${p.id}')">
              <svg viewBox="0 0 24 24"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"></path></svg>
            </button>
          </div>
          <div class="prod-info">
            <div class="prod-supplier">${p.supplier}</div>
            <div class="prod-title">${p.name}</div>
            <div class="prod-price-row">
              <div class="prod-price">&#8377;${p.price}</div>
              <div class="prod-unit">${p.unit}</div>
            </div>
            <button class="btn-add-cart" onclick="event.stopPropagation(); quickAddToCart('${p.id}')">
              + Add to Cart
            </button>
          </div>
        </div>
      `).join('');
    }

    function filterCategory(el, type) {
      document.querySelectorAll('#screen-s2 .chip').forEach(c => c.classList.remove('active'));
      el.classList.add('active');
      if (type === 'all') renderCategoryProducts(PRODUCTS);
      else if (type === 'opc') renderCategoryProducts(PRODUCTS.filter(p => p.subType === 'opc'));
      else if (type === 'ppc') renderCategoryProducts(PRODUCTS.filter(p => p.subType === 'ppc'));
      else if (type === 'rmc') renderCategoryProducts(PRODUCTS.filter(p => p.category === 'cement'));
    }

    // Open Product Detail
    function openProductDetail(productId) {
      const p = PRODUCTS.find(x => x.id === productId) || PRODUCTS[0];
      selectedProductForDetail = p;
      detailSelectedQty = p.moq || 25;

      document.getElementById('detailImg').src = p.image;
      document.getElementById('detailSupplier').textContent = p.supplier;
      document.getElementById('detailTitle').textContent = p.name;
      document.getElementById('detailPrice').innerHTML = '&#8377;' + p.price;
      document.getElementById('detailUnit').textContent = 'per ' + p.unit;
      document.getElementById('detailGrade').textContent = p.grade;
      document.getElementById('detailQty').textContent = detailSelectedQty;

      updateDetailPriceCalc();
      switchScreen('s3');
    }

    function updateDetailQty(delta) {
      const min = selectedProductForDetail.moq || 1;
      detailSelectedQty = Math.max(min, detailSelectedQty + delta);
      document.getElementById('detailQty').textContent = detailSelectedQty;
      updateDetailPriceCalc();
    }

    function updateDetailPriceCalc() {
      const total = detailSelectedQty * selectedProductForDetail.price;
      document.getElementById('detailTotalPrice').innerHTML = '&#8377;' + total.toLocaleString() + ' &rarr;';
      if (selectedProductForDetail.category === 'cement') {
        const kg = detailSelectedQty * 50;
        document.getElementById('detailWeight').textContent = kg.toLocaleString() + ' kg (' + (kg/1000).toFixed(2) + ' Ton)';
      } else {
        document.getElementById('detailWeight').textContent = detailSelectedQty + ' units';
      }
    }

    function addCurrentDetailToCart() {
      const existing = cart.find(item => item.product.id === selectedProductForDetail.id);
      if (existing) {
        existing.quantity += detailSelectedQty;
      } else {
        cart.push({ product: selectedProductForDetail, quantity: detailSelectedQty });
      }
      renderCart();
      switchScreen('s4');
    }

    function quickAddToCart(productId) {
      const p = PRODUCTS.find(x => x.id === productId);
      if (!p) return;
      const existing = cart.find(item => item.product.id === p.id);
      if (existing) {
        existing.quantity += (p.moq || 5);
      } else {
        cart.push({ product: p, quantity: (p.moq || 25) });
      }
      renderCart();
      switchScreen('s4');
    }

    // Cart Management
    function renderCart() {
      const container = document.getElementById('cartItemsContainer');
      const totalItems = cart.reduce((sum, item) => sum + item.quantity, 0);

      document.getElementById('cartCountBadge').textContent = cart.length;
      document.getElementById('bottomNavCartBadge').textContent = cart.length;

      if (cart.length === 0) {
        container.innerHTML = `
          <div style="padding: 40px 20px; text-align: center; color: var(--text-muted);">
            <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" style="margin-bottom: 10px;"><circle cx="9" cy="21" r="1"></circle><circle cx="20" cy="21" r="1"></circle><path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"></path></svg>
            <div style="font-size: 0.95rem; font-weight: 700; color: var(--primary);">Your Cart is Empty</div>
            <div style="font-size: 0.75rem; margin-top: 4px;">Add cement, steel, or bricks to get site delivery quotes.</div>
            <button class="btn-primary-cta" style="margin: 20px auto 0; padding: 10px 18px;" onclick="switchScreen('s2')">
              Browse Materials
            </button>
          </div>
        `;
        document.getElementById('billSubtotal').innerHTML = '&#8377;0';
        document.getElementById('billDelivery').innerHTML = '&#8377;0';
        document.getElementById('billGst').innerHTML = '&#8377;0';
        document.getElementById('billGrandTotal').innerHTML = '&#8377;0';
        document.getElementById('btnCheckoutTotal').innerHTML = '&#8377;0 &rarr;';
        document.getElementById('btnCheckout').disabled = true;
        return;
      }

      document.getElementById('btnCheckout').disabled = false;

      let subtotal = 0;
      container.innerHTML = cart.map((item, idx) => {
        const lineTotal = item.quantity * item.product.price;
        subtotal += lineTotal;
        return `
          <div class="cart-item-card">
            <img class="cart-item-img" src="${item.product.image}" alt="${item.product.name}" onerror="this.src='https://images.unsplash.com/photo-1541888946425-d0fbb18615f8?w=200'">
            <div class="cart-item-info">
              <div style="font-size: 0.8rem; font-weight: 700; color: var(--primary);">${item.product.name}</div>
              <div style="font-size: 0.7rem; color: var(--text-muted);">&#8377;${item.product.price} / ${item.product.unit}</div>
              <div style="font-size: 0.85rem; font-weight: 800; color: var(--primary); margin-top: 4px;">&#8377;${lineTotal.toLocaleString()}</div>
            </div>
            <div class="btn-qty-control">
              <button class="qty-btn" onclick="updateCartItemQty(${idx}, -5)">-</button>
              <span class="qty-text" style="padding: 0 8px;">${item.quantity}</span>
              <button class="qty-btn" onclick="updateCartItemQty(${idx}, 5)">+</button>
            </div>
          </div>
        `;
      }).join('');

      const delivery = subtotal > 0 ? 800 : 0;
      const gst = Math.round(subtotal * 0.18);
      const grandTotal = subtotal + delivery + gst;

      document.getElementById('billSubtotal').innerHTML = '&#8377;' + subtotal.toLocaleString();
      document.getElementById('billDelivery').innerHTML = '&#8377;' + delivery.toLocaleString();
      document.getElementById('billGst').innerHTML = '&#8377;' + gst.toLocaleString();
      document.getElementById('billGrandTotal').innerHTML = '&#8377;' + grandTotal.toLocaleString();
      document.getElementById('btnCheckoutTotal').innerHTML = '&#8377;' + grandTotal.toLocaleString() + ' &rarr;';
      document.getElementById('checkoutFinalAmount').innerHTML = '&#8377;' + grandTotal.toLocaleString() + ' &rarr;';
    }

    function updateCartItemQty(index, delta) {
      if (!cart[index]) return;
      cart[index].quantity += delta;
      if (cart[index].quantity <= 0) {
        cart.splice(index, 1);
      }
      renderCart();
    }

    function clearCart() {
      cart = [];
      renderCart();
    }

    // Checkout & Order Placement Simulation
    function placeSimulatedOrder() {
      if (cart.length === 0) {
        alert('Cart is empty. Please add construction materials first.');
        return;
      }

      const orderId = '#BT0' + nextOrderCounter++;
      let subtotal = 0;
      const itemsList = cart.map(i => {
        const cost = i.quantity * i.product.price;
        subtotal += cost;
        return {
          name: i.product.name,
          qty: i.quantity + ' ' + (i.product.category === 'cement' ? 'Bags' : 'units'),
          price: cost
        };
      });

      const grandTotal = subtotal + 800 + Math.round(subtotal * 0.18);

      const newOrder = {
        id: orderId,
        date: 'Today, Just Now',
        status: 'In Transit',
        statusClass: 'active',
        items: itemsList,
        total: grandTotal,
        site: 'Plot 42, Sector 62'
      };

      orders.unshift(newOrder);
      currentActiveOrder = newOrder;

      // Update Placed Screen
      document.getElementById('placedOrderIdBadge').textContent = 'Order ID: ' + orderId;

      // Clear cart
      cart = [];
      renderCart();
      renderOrders();

      // Show Screen 06 (Order Placed)
      switchScreen('s6');
    }

    function trackCurrentPlacedOrder() {
      if (!currentActiveOrder && orders.length > 0) {
        currentActiveOrder = orders[0];
      }
      if (currentActiveOrder) {
        showTrackingForOrder(currentActiveOrder.id);
      } else {
        switchScreen('s8');
      }
    }

    function showTrackingForOrder(orderId) {
      const order = orders.find(o => o.id === orderId) || orders[0];
      currentActiveOrder = order;

      document.getElementById('trackOrderId').textContent = order.id;
      document.getElementById('trackOrderDate').textContent = 'Placed ' + order.date;
      document.getElementById('trackStatusBadge').textContent = order.status;

      const manifest = document.getElementById('trackItemsManifest');
      manifest.innerHTML = order.items.map(item => `
        <div style="display: flex; justify-content: space-between; font-size: 0.75rem; padding: 4px 0; border-bottom: 1px dashed var(--border);">
          <span style="font-weight: 700; color: var(--primary);">${item.name}</span>
          <span style="color: var(--text-muted);">${item.qty} &bull; &#8377;${item.price.toLocaleString()}</span>
        </div>
      `).join('') + `
        <div style="display: flex; justify-content: space-between; font-size: 0.8rem; font-weight: 800; color: var(--primary); padding-top: 8px;">
          <span>Total Billed:</span>
          <span>&#8377;${order.total.toLocaleString()}</span>
        </div>
      `;

      switchScreen('s7');
    }

    // Render Orders Screen
    function renderOrders(filter = 'all') {
      const container = document.getElementById('ordersListContainer');
      const filtered = orders.filter(o => {
        if (filter === 'all') return true;
        if (filter === 'processing') return o.status === 'In Transit' || o.status === 'Processing';
        if (filter === 'delivered') return o.status === 'Delivered';
        if (filter === 'cancelled') return o.status === 'Cancelled';
        return true;
      });

      if (filtered.length === 0) {
        container.innerHTML = '<div style="padding: 30px; text-align: center; color: var(--text-muted); font-size: 0.8rem;">No orders found in this category.</div>';
        return;
      }

      container.innerHTML = filtered.map(o => `
        <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 14px; padding: 14px; margin-bottom: 12px; box-shadow: var(--shadow-sm);">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
            <span style="font-size: 0.9rem; font-weight: 800; color: var(--primary);">${o.id}</span>
            <span style="background: ${o.status === 'Cancelled' ? '#FEE2E2' : o.status === 'Delivered' ? '#ECFDF5' : '#FEF3C7'}; color: ${o.status === 'Cancelled' ? '#991B1B' : o.status === 'Delivered' ? '#065F46' : '#92400E'}; font-size: 0.68rem; font-weight: 800; padding: 2px 8px; border-radius: 12px;">
              ${o.status}
            </span>
          </div>
          <div style="font-size: 0.72rem; color: var(--text-muted); margin-bottom: 8px;">${o.date} &bull; ${o.site}</div>
          <div style="background: #F8FAFC; border-radius: 8px; padding: 8px; margin-bottom: 10px;">
            ${o.items.map(it => `
              <div style="font-size: 0.75rem; font-weight: 700; color: var(--text-main);">${it.name} (${it.qty})</div>
            `).join('')}
          </div>
          <div style="display: flex; justify-content: space-between; align-items: center;">
            <div style="font-size: 0.9rem; font-weight: 800; color: var(--primary);">&#8377;${o.total.toLocaleString()}</div>
            <div style="display: flex; gap: 8px;">
              <button onclick="showTrackingForOrder('${o.id}')" style="background: #EEF2F6; border: none; border-radius: 6px; padding: 6px 10px; font-size: 0.72rem; font-weight: 700; color: var(--primary); cursor: pointer;">
                Track
              </button>
              <button onclick="reorderFromPast('${o.id}')" style="background: var(--primary); border: none; border-radius: 6px; padding: 6px 10px; font-size: 0.72rem; font-weight: 700; color: white; cursor: pointer;">
                Repeat
              </button>
            </div>
          </div>
        </div>
      `).join('');
    }

    function filterOrderTab(el, filter) {
      document.querySelectorAll('#screen-s8 .chip').forEach(c => c.classList.remove('active'));
      el.classList.add('active');
      renderOrders(filter);
    }

    function promptCancelCurrentOrder() {
      switchScreen('s11');
    }

    function confirmCancelOrder() {
      if (currentActiveOrder) {
        currentActiveOrder.status = 'Cancelled';
        renderOrders();
        alert('Order ' + currentActiveOrder.id + ' has been cancelled. Dispatch desk has been notified.');
        switchScreen('s8');
      }
    }

    function reorderFromPast(orderId) {
      const o = orders.find(x => x.id === orderId);
      if (o) {
        cart.push({ product: PRODUCTS[0], quantity: 25 });
        renderCart();
        switchScreen('s4');
      }
    }

    // Repeat Orders screen
    function renderRepeatOrders() {
      const container = document.getElementById('repeatOrdersContainer');
      container.innerHTML = PRODUCTS.slice(0, 3).map(p => `
        <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 12px; margin-bottom: 10px; display: flex; align-items: center; justify-content: space-between;">
          <div style="display: flex; align-items: center; gap: 10px;">
            <img src="${p.image}" alt="${p.name}" style="width: 44px; height: 44px; border-radius: 8px; object-fit: cover;">
            <div>
              <div style="font-size: 0.8rem; font-weight: 700; color: var(--primary);">${p.name}</div>
              <div style="font-size: 0.7rem; color: var(--text-muted);">&#8377;${p.price} / ${p.unit} &bull; Min ${p.moq || 25}</div>
            </div>
          </div>
          <button onclick="quickAddToCart('${p.id}')" style="background: var(--primary); color: white; border: none; border-radius: 6px; padding: 6px 10px; font-size: 0.72rem; font-weight: 700; cursor: pointer;">
            + Reorder
          </button>
        </div>
      `).join('');
    }

    // Wishlist
    function renderWishlist() {
      const container = document.getElementById('wishlistContainer');
      if (wishlist.length === 0) {
        container.innerHTML = '<div style="padding: 30px; text-align: center; color: var(--text-muted); font-size: 0.8rem;">No saved materials in wishlist.</div>';
        return;
      }
      container.innerHTML = wishlist.map(p => `
        <div style="background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 12px; margin-bottom: 10px; display: flex; align-items: center; justify-content: space-between;">
          <div style="display: flex; align-items: center; gap: 10px;" onclick="openProductDetail('${p.id}')">
            <img src="${p.image}" alt="${p.name}" style="width: 48px; height: 48px; border-radius: 8px; object-fit: cover;">
            <div>
              <div style="font-size: 0.8rem; font-weight: 700; color: var(--primary);">${p.name}</div>
              <div style="font-size: 0.72rem; color: var(--text-muted);">&#8377;${p.price} / ${p.unit}</div>
            </div>
          </div>
          <button onclick="quickAddToCart('${p.id}')" style="background: var(--primary); color: white; border: none; border-radius: 6px; padding: 6px 10px; font-size: 0.72rem; font-weight: 700; cursor: pointer;">
            Move to Cart
          </button>
        </div>
      `).join('');
    }

    function toggleWishlist(productId) {
      const p = PRODUCTS.find(x => x.id === productId);
      if (!p) return;
      const idx = wishlist.findIndex(w => w.id === productId);
      if (idx >= 0) wishlist.splice(idx, 1);
      else wishlist.push(p);
      renderWishlist();
      alert('Wishlist updated.');
    }

    function toggleWishlistCurrent() {
      if (selectedProductForDetail) {
        toggleWishlist(selectedProductForDetail.id);
      }
    }

    // Notifications
    function renderNotifications() {
      const container = document.getElementById('notificationsContainer');
      container.innerHTML = notifications.map(n => `
        <div style="background: ${n.unread ? '#F0F9FF' : 'var(--surface)'}; border: 1px solid ${n.unread ? '#BAE6FD' : 'var(--border)'}; border-radius: 12px; padding: 12px; margin-bottom: 10px;">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
            <span style="font-size: 0.8rem; font-weight: 800; color: var(--primary);">${n.title}</span>
            <span style="font-size: 0.65rem; color: var(--text-muted);">${n.time}</span>
          </div>
          <div style="font-size: 0.72rem; color: var(--text-main); line-height: 1.35;">${n.body}</div>
        </div>
      `).join('');
    }

    function markAllNotificationsRead() {
      notifications.forEach(n => n.unread = false);
      renderNotifications();
    }

    function submitRfqDemo() {
      alert('Institutional RFQ submitted successfully! Regional Plant Sales will respond with quotation within 2 business hours.');
      switchScreen('s1');
    }

    // Start prototype
    init();
  </script>
</body>
</html>
'''

output_path = r'D:\BuildDo\Buildto\demo\preview\index.html'
with open(output_path, 'w', encoding='utf-8') as f:
    f.write(html_content)

print(f"Generated {output_path} successfully. Size: {len(html_content)} bytes")
