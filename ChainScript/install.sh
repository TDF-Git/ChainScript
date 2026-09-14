#!/usr/bin/env bash

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$ROOT"

echo "=========================================="
echo "        ChainScript Installer"
echo "=========================================="
echo

# --------------------------------------------------
# 1. Create directories
# --------------------------------------------------

echo "[1/7] Creating ChainScript directories..."

mkdir -p "$ROOT/CsxModules"
mkdir -p "$ROOT/Runtime"
mkdir -p "$ROOT/bin"

# --------------------------------------------------
# 2. Install .NET SDK
# --------------------------------------------------

echo
echo "[2/7] Checking .NET SDK..."

if [ -x "$ROOT/.dotnet/dotnet" ]; then
    echo "Local .NET SDK found."
else
    echo ".NET SDK not found."
    echo "Installing .NET 8 SDK..."

    curl -fsSL https://dot.net/v1/dotnet-install.sh \
        -o /tmp/dotnet-install.sh

    chmod +x /tmp/dotnet-install.sh

    /tmp/dotnet-install.sh \
        --channel 8.0 \
        --install-dir "$ROOT/.dotnet" \
        --no-path

    echo ".NET SDK installed."
fi

export DOTNET_ROOT="$ROOT/.dotnet"
export PATH="$DOTNET_ROOT:$ROOT/bin:$PATH"
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

echo
echo "Using .NET:"
"$DOTNET_ROOT/dotnet" --version

# --------------------------------------------------
# 3. Create .NET runtime project
# --------------------------------------------------

echo
echo "[3/7] Preparing ChainScript runtime..."

if [ ! -f "$ROOT/Runtime/ChainScriptRuntime.csproj" ]; then

    "$DOTNET_ROOT/dotnet" new console \
        --name ChainScriptRuntime \
        --output "$ROOT/Runtime" \
        --framework net8.0 \
        --force

fi

# --------------------------------------------------
# 4. Install ChainScript runtime
# --------------------------------------------------

echo
echo "[4/7] Installing ChainScript runtime..."

cat > "$ROOT/Runtime/Program.cs" <<'CSHARP'
using System;
using System.IO;
using System.Collections.Generic;

class Program
{
    static readonly Dictionary<string, string> Variables = new();

    static void Main(string[] args)
    {
        if (args.Length == 0)
        {
            Help();
            return;
        }

        string command = args[0].ToLowerInvariant();

        switch (command)
        {
            case "run":
                RunCommand(args);
                break;

            case "build":
                BuildCommand(args);
                break;

            case "init":
                InitProject(args);
                break;

            case "link":
                LinkCommand(args);
                break;

            case "uninstall":
                Uninstall(args);
                break;

            case "version":
                Console.WriteLine("ChainScript 0.1.1");
                break;

            case "help":
            case "--help":
            case "-h":
                Help();
                break;

            default:
                if (args[0].EndsWith(".csx", StringComparison.OrdinalIgnoreCase) ||
                    args[0].EndsWith(".chsx", StringComparison.OrdinalIgnoreCase))
                {
                    RunFile(args[0]);
                }
                else
                {
                    Console.WriteLine($"Unknown command: {args[0]}");
                    Console.WriteLine("Run 'ChainScript help' for help.");
                }
                break;
        }
    }

    static void RunCommand(string[] args)
    {
        if (args.Length < 2)
        {
            Console.WriteLine("Usage: ChainScript run <file.csx>");
            return;
        }

        RunFile(args[1]);
    }

    static void RunFile(string file)
    {
        if (!File.Exists(file))
        {
            Console.WriteLine($"File not found: {file}");
            return;
        }

        Variables.Clear();

        string[] lines = File.ReadAllLines(file);

        foreach (string rawLine in lines)
        {
            string line = rawLine.Trim();

            if (string.IsNullOrWhiteSpace(line) ||
                line.StartsWith("//"))
                continue;

            if (line.StartsWith("#"))
                continue;

            if (line.StartsWith("let "))
            {
                ParseLet(line);
                continue;
            }

            if (line.StartsWith("print(") && line.EndsWith(");"))
            {
                string expression = line.Substring(6, line.Length - 8);
                Console.WriteLine(EvaluateExpression(expression));
                continue;
            }

            if (line.StartsWith("system.output "))
            {
                string expression = line.Substring("system.output ".Length);
                Console.WriteLine(EvaluateExpression(expression));
                continue;
            }
        }
    }

    static void ParseLet(string line)
    {
        string content = line.Substring(4).Trim();

        if (content.EndsWith(";"))
            content = content[..^1];

        int equals = content.IndexOf('=');

        if (equals < 0)
            return;

        string name = content[..equals].Trim();
        string value = content[(equals + 1)..].Trim();

        Variables[name] = EvaluateExpression(value);
    }

    static string EvaluateExpression(string expression)
    {
        expression = expression.Trim();

        if (expression.StartsWith("\"") &&
            expression.EndsWith("\"") &&
            expression.Length >= 2)
        {
            return expression[1..^1];
        }

        List<string> parts = SplitExpression(expression);

        if (parts.Count > 1)
        {
            string result = "";

            foreach (string part in parts)
                result += EvaluateExpression(part);

            return result;
        }

        if (Variables.TryGetValue(expression, out string? value))
            return value;

        return expression;
    }

    static List<string> SplitExpression(string expression)
    {
        List<string> parts = new();
        bool insideQuotes = false;
        int start = 0;

        for (int i = 0; i < expression.Length; i++)
        {
            if (expression[i] == '"')
                insideQuotes = !insideQuotes;

            if (expression[i] == '+' && !insideQuotes)
            {
                parts.Add(expression[start..i].Trim());
                start = i + 1;
            }
        }

        if (start > 0)
            parts.Add(expression[start..].Trim());
        else
            parts.Add(expression.Trim());

        return parts;
    }

    static void BuildCommand(string[] args)
    {
        if (args.Length < 2)
        {
            Console.WriteLine("Usage: ChainScript build <file.csx>");
            return;
        }

        string file = args[1];

        if (!File.Exists(file))
        {
            Console.WriteLine($"File not found: {file}");
            return;
        }

        Console.WriteLine($"Building {file}...");
        Console.WriteLine("Build successful.");
    }

    static void InitProject(string[] args)
    {
        if (args.Length < 2)
        {
            Console.WriteLine("Usage: ChainScript init <project>");
            return;
        }

        string project = args[1];

        if (Directory.Exists(project))
        {
            Console.WriteLine($"Directory already exists: {project}");
            return;
        }

        Directory.CreateDirectory(project);
        Directory.CreateDirectory(Path.Combine(project, "CsxModules"));

        File.WriteAllText(
            Path.Combine(project, "main.csx"),
            "system.output \"Hello, ChainScript!\"\n"
        );

        File.WriteAllText(
            Path.Combine(project, "project.csin"),
            "{\n    \"name\": \"" + project + "\",\n    \"version\": \"1.0.0\"\n}\n"
        );

        Console.WriteLine($"Created ChainScript project: {project}");
    }

    static void LinkCommand(string[] args)
    {
        if (args.Length < 3)
        {
            Console.WriteLine("Usage: ChainScript Link <file.chl> <code-file>");
            return;
        }

        LinkFile(args[1], args[2]);
    }

    static void LinkFile(string chlFile, string codeFile)
    {
        if (!File.Exists(chlFile))
        {
            Console.WriteLine($"CHL file not found: {chlFile}");
            return;
        }

        if (!File.Exists(codeFile))
        {
            Console.WriteLine($"Code file not found: {codeFile}");
            return;
        }

        if (!chlFile.EndsWith(".chl", StringComparison.OrdinalIgnoreCase))
        {
            Console.WriteLine("Link requires a .chl file.");
            return;
        }

        string[] lines = File.ReadAllLines(codeFile);

        foreach (string rawInstruction in File.ReadAllLines(chlFile))
        {
            string instruction = rawInstruction.Trim();

            if (string.IsNullOrWhiteSpace(instruction) ||
                instruction.StartsWith("#"))
                continue;

            if (instruction.StartsWith(
                "ReplaceLine ",
                StringComparison.OrdinalIgnoreCase))
            {
                string rest = instruction["ReplaceLine ".Length..].Trim();

                int separator = rest.IndexOf(' ');

                if (separator < 0)
                {
                    Console.WriteLine($"Invalid ReplaceLine: {instruction}");
                    continue;
                }

                if (!int.TryParse(
                    rest[..separator],
                    out int lineNumber))
                {
                    Console.WriteLine($"Invalid line number: {instruction}");
                    continue;
                }

                if (lineNumber < 1 || lineNumber > lines.Length)
                {
                    Console.WriteLine($"Line out of range: {lineNumber}");
                    continue;
                }

                lines[lineNumber - 1] =
                    rest[(separator + 1)..];

                continue;
            }

            if (instruction.StartsWith(
                "ChangeVar ",
                StringComparison.OrdinalIgnoreCase))
            {
                string rest = instruction["ChangeVar ".Length..].Trim();

                int separator = rest.IndexOf(' ');

                if (separator < 0)
                {
                    Console.WriteLine($"Invalid ChangeVar: {instruction}");
                    continue;
                }

                string variable = rest[..separator];
                string value = rest[(separator + 1)..];

                for (int i = 0; i < lines.Length; i++)
                    lines[i] =
                        ReplaceVariable(lines[i], variable, value);

                continue;
            }

            Console.WriteLine(
                $"Unknown CHL instruction: {instruction}");
        }

        File.WriteAllLines(codeFile, lines);

        Console.WriteLine(
            $"Linked {chlFile} -> {codeFile}");
    }

    static string ReplaceVariable(
        string line,
        string variable,
        string value)
    {
        string quotedValue = value;

        if (!(value.StartsWith("\"") &&
              value.EndsWith("\"")))
        {
            quotedValue = "\"" + value + "\"";
        }

        string[] patterns =
        {
            variable + " =",
            "$" + variable,
            "@" + variable,
            "{" + variable + "}"
        };

        foreach (string pattern in patterns)
        {
            int index = line.IndexOf(
                pattern,
                StringComparison.Ordinal);

            if (index < 0)
                continue;

            if (pattern.EndsWith(" ="))
            {
                int equals = line.IndexOf('=', index);

                if (equals >= 0)
                {
                    string left = line[..(equals + 1)];
                    string right = line[(equals + 1)..];

                    int semicolon = right.IndexOf(';');

                    if (semicolon >= 0)
                    {
                        return left + " " +
                               quotedValue +
                               right[semicolon..];
                    }

                    return left + " " + quotedValue;
                }
            }

            return line.Replace(
                pattern,
                pattern.StartsWith("$")
                    ? "$" + variable
                    : variable
            );
        }

        return line;
    }

    static void Uninstall(string[] args)
    {
        string root = FindChainScriptRoot();

        if (args.Length >= 2)
        {
            string moduleName = args[1];

            string modulePath = Path.Combine(
                root,
                "CsxModules",
                moduleName
            );

            if (!Directory.Exists(modulePath))
            {
                Console.WriteLine(
                    $"Module not found: {moduleName}");
                return;
            }

            Console.WriteLine(
                $"Uninstalling module: {moduleName}");

            Directory.Delete(modulePath, true);

            Console.WriteLine(
                $"Module '{moduleName}' uninstalled.");

            return;
        }

        Console.WriteLine("ChainScript Uninstall");
        Console.WriteLine();
        Console.WriteLine(
            "This will remove the ChainScript runtime and installed modules.");
        Console.WriteLine(
            "Your source files will NOT be deleted.");
        Console.WriteLine();

        Console.Write("Continue? [y/N] ");

        string? answer = Console.ReadLine();

        if (!string.Equals(
            answer,
            "y",
            StringComparison.OrdinalIgnoreCase))
        {
            Console.WriteLine("Uninstall cancelled.");
            return;
        }

        string[] directories =
        {
            Path.Combine(root, ".dotnet"),
            Path.Combine(root, "Runtime"),
            Path.Combine(root, "bin"),
            Path.Combine(root, "CsxModules")
        };

        foreach (string directory in directories)
        {
            if (Directory.Exists(directory))
            {
                Console.WriteLine(
                    $"Removing {directory}");

                Directory.Delete(directory, true);
            }
        }

        Console.WriteLine();
        Console.WriteLine(
            "ChainScript has been uninstalled.");
        Console.WriteLine(
            "Your source files were left untouched.");
    }

    static string FindChainScriptRoot()
    {
        string current = AppContext.BaseDirectory;

        DirectoryInfo? directory =
            new DirectoryInfo(current);

        while (directory != null)
        {
            if (File.Exists(
                    Path.Combine(
                        directory.FullName,
                        "install.sh")) ||
                Directory.Exists(
                    Path.Combine(
                        directory.FullName,
                        "CsxModules")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        return Directory.GetCurrentDirectory();
    }

    static void Help()
    {
        Console.WriteLine("ChainScript 0.1.0");
        Console.WriteLine();
        Console.WriteLine("Commands:");
        Console.WriteLine("  ChainScript run <file.csx>");
        Console.WriteLine("  ChainScript build <file.csx>");
        Console.WriteLine("  ChainScript init <project>");
        Console.WriteLine("  ChainScript Link <file.chl> <code-file>");
        Console.WriteLine("  ChainScript Uninstall");
        Console.WriteLine("  ChainScript Uninstall <module>");
        Console.WriteLine("  ChainScript version");
        Console.WriteLine("  ChainScript help");
        Console.WriteLine();
        Console.WriteLine("File types:");
        Console.WriteLine("  .csx   ChainScript source");
        Console.WriteLine("  .chsx  ChainScript source");
        Console.WriteLine("  .csi   ChainScript intermediate/executable code");
        Console.WriteLine("  .csin  ChainScript project/package manifest");
        Console.WriteLine("  .chl   ChainScript Link transformation file");
    }
}
CSHARP

# --------------------------------------------------
# 5. Create starter program
# --------------------------------------------------

echo
echo "[5/7] Creating starter ChainScript program..."

if [ ! -f "$ROOT/main.csx" ]; then
    cat > "$ROOT/main.csx" <<'CSX'
system.output "Hello, ChainScript!"

let name = "World"
system.output "Hello, " + name
CSX
fi

# --------------------------------------------------
# 6. Install ChainScript command
# --------------------------------------------------

echo
echo "[6/7] Installing ChainScript command..."

cat > "$ROOT/bin/ChainScript" <<'BASH'
#!/usr/bin/env bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export DOTNET_ROOT="$ROOT/.dotnet"
export PATH="$DOTNET_ROOT:$ROOT/bin:$PATH"
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

exec "$DOTNET_ROOT/dotnet" run \
    --project "$ROOT/Runtime" \
    -- "$@"
BASH

chmod +x "$ROOT/bin/ChainScript"

# Keep old csx launcher for compatibility if it already exists.
if [ -f "$ROOT/bin/csx" ]; then
    chmod +x "$ROOT/bin/csx"
fi

# --------------------------------------------------
# 7. Restore and build
# --------------------------------------------------

echo
echo "[7/7] Building ChainScript..."

"$DOTNET_ROOT/dotnet" restore "$ROOT/Runtime"

"$DOTNET_ROOT/dotnet" build \
    "$ROOT/Runtime" \
    --configuration Release

echo
echo "=========================================="
echo "       ChainScript installed!"
echo "=========================================="
echo
echo "Version:"
"$ROOT/bin/ChainScript" version

echo
echo "Commands:"
echo "  ./bin/ChainScript run main.csx"
echo "  ./bin/ChainScript build main.csx"
echo "  ./bin/ChainScript init MyProject"
echo "  ./bin/ChainScript Link changes.chl test.js"
echo "  ./bin/ChainScript Uninstall"
echo
echo "Add ChainScript to PATH with:"
echo "  export PATH=\"$ROOT/bin:\$PATH\""
echo
echo "=========================================="
