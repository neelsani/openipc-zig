import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { WebAssemblyProvider } from './contexts/WasmContext.tsx'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <WebAssemblyProvider>
      <App />
    </WebAssemblyProvider>
  </StrictMode>,
)
