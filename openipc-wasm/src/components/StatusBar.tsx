import React from 'react';
import { Loader2, CheckCircle, XCircle, Info } from 'lucide-react';

interface StatusBarProps {
  status: string;
  isLoading: boolean;
  webCodecsSupported: boolean;
}

export const StatusBar: React.FC<StatusBarProps> = ({
  status,
  isLoading,
  webCodecsSupported
}) => {
  return (
    <div className="flex items-center justify-between bg-white rounded-lg shadow-md p-4">
      <div className="flex items-center gap-3">
        {isLoading && <Loader2 className="w-5 h-5 animate-spin text-blue-500" />}
        <Info className="w-5 h-5 text-gray-500" />
        <span className="font-medium text-gray-700">{status}</span>
      </div>
      
      <div className="flex items-center gap-2">
        {webCodecsSupported ? (
          <>
            <CheckCircle className="w-5 h-5 text-green-500" />
            <span className="text-sm text-green-600">WebCodecs supported</span>
          </>
        ) : (
          <>
            <XCircle className="w-5 h-5 text-red-500" />
            <span className="text-sm text-red-600">WebCodecs not supported</span>
          </>
        )}
      </div>
    </div>
  );
};
