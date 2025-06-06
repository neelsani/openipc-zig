// src/components/OutputConsole.tsx
import React, { useEffect, useRef, useState } from 'react';
import { Terminal, ArrowDown, Pause } from 'lucide-react';

interface OutputConsoleProps {
  output: string;
  className?: string;
}

export const OutputConsole: React.FC<OutputConsoleProps> = ({
  output,
  className = 'h-64'
}) => {
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const [autoScroll, setAutoScroll] = useState(true);
  const [isAtBottom, setIsAtBottom] = useState(true);
  const isAutoScrollingRef = useRef(false); // Track if we're auto-scrolling

  // Auto-scroll to bottom when output changes (only if auto-scroll is enabled)
  useEffect(() => {
    if (textareaRef.current && autoScroll) {
      isAutoScrollingRef.current = true; // Mark that we're about to auto-scroll
      textareaRef.current.scrollTop = textareaRef.current.scrollHeight;
      
      // Reset the flag after a short delay to allow the scroll event to fire
      setTimeout(() => {
        isAutoScrollingRef.current = false;
      }, 50);
    }
    setAutoScroll(true);
  }, [output, autoScroll]);

  

  // Manual scroll to bottom
  const scrollToBottom = () => {
    if (textareaRef.current) {
      isAutoScrollingRef.current = true;
      textareaRef.current.scrollTop = textareaRef.current.scrollHeight;
      setAutoScroll(true);
      setIsAtBottom(true);
      
      setTimeout(() => {
        isAutoScrollingRef.current = false;
      }, 50);
    }
  };

  return (
    <div className="bg-white rounded-lg shadow-md p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-gray-900 flex items-center gap-2">
          <Terminal className="w-5 h-5" />
          Debug Output
        </h3>
        
        <div className="flex items-center gap-2">
          <button
            onClick={() => setAutoScroll(!autoScroll)}
            className={`p-2 rounded-lg transition-colors ${
              autoScroll 
                ? 'bg-green-100 text-green-600 hover:bg-green-200' 
                : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
            }`}
            title={autoScroll ? 'Disable auto-scroll' : 'Enable auto-scroll'}
          >
            <Pause className="w-4 h-4" />
          </button>
          
          {!isAtBottom && (
            <button
              onClick={scrollToBottom}
              className="p-2 bg-blue-100 text-blue-600 hover:bg-blue-200 rounded-lg transition-colors"
              title="Scroll to bottom"
            >
              <ArrowDown className="w-4 h-4" />
            </button>
          )}
        </div>
      </div>
      
      <textarea
        ref={textareaRef}
        value={output}
        readOnly
        placeholder="Debug output will appear here..."
        className={`w-full p-4 font-mono text-sm bg-gray-900 text-green-400 border border-gray-300 rounded-lg resize-none focus:outline-none ${className}`}
      />
    </div>
  );
};
