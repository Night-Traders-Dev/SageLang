import { useState } from "react";

const MAX_CODE_LENGTH = 100000;

function App() {
  const [code, setCode] = useState(`// SageLang Hello World
proc main():
    print("Hello from SageLang!")
`);
  const [output, setOutput] = useState("");
  const [warning, setWarning] = useState("");

  const handleRun = () => {
    if (code.length > MAX_CODE_LENGTH) {
      setOutput("Error: Code size limit exceeded.");
      return;
    }
    setOutput("Compiling...\n[SageLang Compiler] Note: Web compilation is currently a mock.\n[Output]:\nHello from SageLang!");
  };

  const handleCodeChange = (newCode: string) => {
    if (newCode.length > MAX_CODE_LENGTH) {
      setCode(newCode.substring(0, MAX_CODE_LENGTH));
      setWarning(`Security Warning: Code editor limit of ${MAX_CODE_LENGTH.toLocaleString()} characters reached (input truncated).`);
    } else {
      setCode(newCode);
      if (newCode.length >= MAX_CODE_LENGTH - 1000) {
        setWarning(`Warning: Approaching code editor limit (${newCode.length.toLocaleString()} / ${MAX_CODE_LENGTH.toLocaleString()} characters).`);
      } else {
        setWarning("");
      }
    }
  };

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-200 font-sans p-8 flex flex-col items-center">
      <div className="max-w-4xl w-full">
        <header className="mb-8">
          <h1 className="text-4xl font-bold text-white mb-2">🌿 SageLang Web Playground</h1>
          <p className="text-neutral-400">
            A clean, indentation-based systems programming language built in C. 
            (Web compiler is mocked as C/Native compilation is not available in the browser).
          </p>
        </header>
        
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="flex flex-col">
            <div className="flex justify-between items-center mb-2">
              <h2 className="text-lg font-semibold text-neutral-300">Editor</h2>
              <button 
                onClick={handleRun}
                className="bg-emerald-600 hover:bg-emerald-500 text-white px-4 py-1.5 rounded text-sm font-medium transition-colors"
              >
                Run
              </button>
            </div>
            {warning && (
              <div className="mb-2 text-xs bg-amber-950/40 border border-amber-800 text-amber-400 p-2.5 rounded font-medium">
                {warning}
              </div>
            )}
            <textarea 
              value={code}
              onChange={(e) => handleCodeChange(e.target.value)}
              className="w-full h-80 bg-neutral-900 border border-neutral-800 rounded p-4 font-mono text-sm focus:outline-none focus:border-emerald-500 text-emerald-400"
              spellCheck="false"
            />
          </div>
          
          <div className="flex flex-col">
            <h2 className="text-lg font-semibold text-neutral-300 mb-2">Output</h2>
            <div className="w-full h-80 bg-neutral-900 border border-neutral-800 rounded p-4 font-mono text-sm whitespace-pre-wrap overflow-y-auto">
              {output || "Output will appear here..."}
            </div>
          </div>
        </div>

        <div className="mt-12 bg-neutral-900 border border-neutral-800 rounded p-6">
          <h2 className="text-2xl font-bold text-white mb-4">About SageLang</h2>
          <ul className="space-y-2 text-neutral-400 list-disc pl-5">
            <li><strong>Core Technology:</strong> C (C11 standard) and SageLang itself.</li>
            <li><strong>Backends:</strong> C Codegen, LLVM IR, Native Assembly, Bytecode VM.</li>
            <li><strong>Memory Management:</strong> Hybrid GC (Concurrent Mark-Sweep, ARC, ORC).</li>
            <li><strong>Syntax:</strong> Indentation-based blocks, snake_case identifiers, PascalCase classes.</li>
          </ul>
        </div>
      </div>
    </div>
  );
}

export default App;
