# xlsx_reader.ps1 - Lectura de .xlsx sin Excel instalado (OpenXML: ZIP + XML).
#
# Expone la misma forma que ingesta_excel.ps1 usaba con Excel COM, para no tocar las ingestas:
#   $book = [FlujoXlsx.Workbook]::new($path)
#   $ws   = $book.Worksheets.Item('RESUMEN')      # o .Item(1), por posicion
#   $ws.UsedRange.Rows.Count
#   $ws.Cells.Item($fila, $col).Value2            # double | string | bool | $null
#   $ws.Cells.Item($fila, $col).Text              # texto mostrado (aproximado al de Excel)
#   $book.Close($false)
#
# Las formulas devuelven el ultimo valor guardado en el archivo: no se recalcula nada
# (a diferencia de Excel, que al abrir recalcula funciones volatiles como HOY()).
#
# Uso: . (Join-Path $PSScriptRoot 'xlsx_reader.ps1')

if (-not ('FlujoXlsx.Workbook' -as [type])) {
    $source = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml;

namespace FlujoXlsx
{
    public sealed class Cell
    {
        private readonly object _value2;
        private readonly string _text;
        private readonly string _formula;

        public Cell(object value2, string text, string formula)
        {
            _value2 = value2;
            _text = text ?? "";
            _formula = formula;
        }

        public object Value2 { get { return _value2; } }
        public string Text { get { return _text; } }
        public string Formula { get { return _formula; } }

        public static readonly Cell Empty = new Cell(null, "", null);
    }

    public sealed class RowsInfo
    {
        private readonly int _count;
        public RowsInfo(int count) { _count = count; }
        public int Count { get { return _count; } }
    }

    public sealed class UsedRangeInfo
    {
        private readonly RowsInfo _rows;
        public UsedRangeInfo(int rows) { _rows = new RowsInfo(rows); }
        public RowsInfo Rows { get { return _rows; } }
    }

    public sealed class CellCollection
    {
        private readonly Dictionary<long, Cell> _cells;
        internal CellCollection(Dictionary<long, Cell> cells) { _cells = cells; }

        public Cell Item(int row, int column)
        {
            Cell cell;
            return _cells.TryGetValue(Key(row, column), out cell) ? cell : Cell.Empty;
        }

        internal static long Key(int row, int column)
        {
            return ((long)row << 20) | (uint)column;
        }
    }

    public sealed class Worksheet
    {
        private readonly string _name;
        private readonly CellCollection _cells;
        private readonly UsedRangeInfo _usedRange;

        internal Worksheet(string name, Dictionary<long, Cell> cells, int usedRows)
        {
            _name = name;
            _cells = new CellCollection(cells);
            _usedRange = new UsedRangeInfo(usedRows);
        }

        public string Name { get { return _name; } }
        public CellCollection Cells { get { return _cells; } }
        public UsedRangeInfo UsedRange { get { return _usedRange; } }
    }

    public sealed class SheetCollection
    {
        private readonly Workbook _book;
        internal SheetCollection(Workbook book) { _book = book; }

        public Worksheet Item(string name) { return _book.GetSheet(name); }
        public Worksheet Item(int index) { return _book.GetSheet(index); }
        public int Count { get { return _book.SheetCount; } }
    }

    public sealed class Workbook : IDisposable
    {
        private const int KindNone = 0, KindDate = 1, KindTime = 2, KindDateTime = 3;
        private const string RelNamespace = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";

        private static readonly Dictionary<string, int> ErrorCodes = new Dictionary<string, int>
        {
            { "#NULL!", -2146826288 }, { "#DIV/0!", -2146826281 }, { "#VALUE!", -2146826273 },
            { "#REF!", -2146826265 }, { "#NAME?", -2146826259 }, { "#NUM!", -2146826252 }, { "#N/A", -2146826246 }
        };

        private readonly FileStream _stream;
        private readonly ZipArchive _zip;
        private readonly Dictionary<string, ZipArchiveEntry> _entries = new Dictionary<string, ZipArchiveEntry>(StringComparer.OrdinalIgnoreCase);
        private readonly List<string> _sheetNames = new List<string>();
        private readonly List<string> _sheetPaths = new List<string>();
        private readonly Dictionary<string, Worksheet> _loaded = new Dictionary<string, Worksheet>(StringComparer.OrdinalIgnoreCase);
        private List<string> _sharedStrings = new List<string>();
        private List<int> _styleKinds = new List<int>();

        public Workbook(string path)
        {
            // FileShare.ReadWrite: no bloquea el archivo si alguien lo tiene abierto (Drive/Excel)
            _stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            try
            {
                _zip = new ZipArchive(_stream, ZipArchiveMode.Read, false);
                foreach (ZipArchiveEntry entry in _zip.Entries)
                    _entries[entry.FullName.Replace('\\', '/').TrimStart('/')] = entry;
                LoadWorkbook();
                _sharedStrings = LoadSharedStrings();
                _styleKinds = LoadStyles();
            }
            catch
            {
                Dispose();
                throw;
            }
        }

        public SheetCollection Worksheets { get { return new SheetCollection(this); } }
        internal int SheetCount { get { return _sheetNames.Count; } }

        public void Close(bool saveChanges) { Dispose(); }

        public void Dispose()
        {
            if (_zip != null) _zip.Dispose();
            if (_stream != null) _stream.Dispose();
        }

        internal Worksheet GetSheet(string name)
        {
            Worksheet ws;
            if (_loaded.TryGetValue(name, out ws)) return ws;
            for (int i = 0; i < _sheetNames.Count; i++)
                if (string.Equals(_sheetNames[i], name, StringComparison.OrdinalIgnoreCase)) return LoadSheet(i);
            throw new ArgumentException("No existe la hoja '" + name + "'. Hojas: " + string.Join(", ", _sheetNames.ToArray()));
        }

        internal Worksheet GetSheet(int index)
        {
            if (index < 1 || index > _sheetNames.Count)
                throw new ArgumentOutOfRangeException("index", "Hoja " + index + " fuera de rango (1.." + _sheetNames.Count + ")");
            Worksheet ws;
            if (_loaded.TryGetValue(_sheetNames[index - 1], out ws)) return ws;
            return LoadSheet(index - 1);
        }

        private ZipArchiveEntry Find(string path)
        {
            ZipArchiveEntry entry;
            return _entries.TryGetValue(path, out entry) ? entry : null;
        }

        private static XmlReader OpenXml(ZipArchiveEntry entry)
        {
            XmlReaderSettings settings = new XmlReaderSettings();
            settings.IgnoreComments = true;
            settings.IgnoreProcessingInstructions = true;
            settings.DtdProcessing = DtdProcessing.Prohibit;
            settings.CloseInput = true;
            return XmlReader.Create(entry.Open(), settings);
        }

        private static string AttributeByLocalName(XmlReader r, string localName)
        {
            string value = null;
            if (r.MoveToFirstAttribute())
            {
                do
                {
                    if (r.LocalName == localName) { value = r.Value; break; }
                } while (r.MoveToNextAttribute());
                r.MoveToElement();
            }
            return value;
        }

        private static bool IsTextNode(XmlNodeType type)
        {
            return type == XmlNodeType.Text || type == XmlNodeType.CDATA
                || type == XmlNodeType.SignificantWhitespace || type == XmlNodeType.Whitespace;
        }

        // Excel escapa caracteres de control como _x000D_
        private static string DecodeEscapes(string s)
        {
            if (s.IndexOf("_x", StringComparison.Ordinal) < 0) return s;
            return Regex.Replace(s, "_x([0-9A-Fa-f]{4})_", m => ((char)Convert.ToInt32(m.Groups[1].Value, 16)).ToString());
        }

        private void LoadWorkbook()
        {
            Dictionary<string, string> rels = new Dictionary<string, string>(StringComparer.Ordinal);
            ZipArchiveEntry relsEntry = Find("xl/_rels/workbook.xml.rels");
            if (relsEntry != null)
            {
                using (XmlReader r = OpenXml(relsEntry))
                {
                    while (r.Read())
                    {
                        if (r.NodeType != XmlNodeType.Element || r.LocalName != "Relationship") continue;
                        string id = r.GetAttribute("Id");
                        string target = r.GetAttribute("Target");
                        if (id != null && target != null) rels[id] = target;
                    }
                }
            }

            ZipArchiveEntry workbookEntry = Find("xl/workbook.xml");
            if (workbookEntry == null) throw new InvalidDataException("No es un .xlsx valido: falta xl/workbook.xml");
            using (XmlReader r = OpenXml(workbookEntry))
            {
                while (r.Read())
                {
                    if (r.NodeType != XmlNodeType.Element || r.LocalName != "sheet") continue;
                    string name = r.GetAttribute("name");
                    string relId = r.GetAttribute("id", RelNamespace) ?? AttributeByLocalName(r, "id");
                    string target;
                    if (name == null || relId == null || !rels.TryGetValue(relId, out target)) continue;
                    _sheetNames.Add(name);
                    _sheetPaths.Add(target.StartsWith("/") ? target.TrimStart('/') : "xl/" + target);
                }
            }
        }

        private List<string> LoadSharedStrings()
        {
            List<string> list = new List<string>();
            ZipArchiveEntry entry = Find("xl/sharedStrings.xml");
            if (entry == null) return list;
            using (XmlReader r = OpenXml(entry))
            {
                StringBuilder sb = null;
                bool inT = false;
                int inPhonetic = 0;
                while (r.Read())
                {
                    if (r.NodeType == XmlNodeType.Element)
                    {
                        if (r.LocalName == "si") { if (r.IsEmptyElement) list.Add(""); else sb = new StringBuilder(); }
                        else if (r.LocalName == "rPh" && !r.IsEmptyElement) inPhonetic++;
                        else if (r.LocalName == "t" && !r.IsEmptyElement) inT = true;
                    }
                    else if (r.NodeType == XmlNodeType.EndElement)
                    {
                        if (r.LocalName == "si") { list.Add(sb == null ? "" : DecodeEscapes(sb.ToString())); sb = null; }
                        else if (r.LocalName == "rPh") inPhonetic--;
                        else if (r.LocalName == "t") inT = false;
                    }
                    else if (inT && inPhonetic == 0 && sb != null && IsTextNode(r.NodeType))
                    {
                        sb.Append(r.Value);
                    }
                }
            }
            return list;
        }

        private List<int> LoadStyles()
        {
            List<int> kinds = new List<int>();
            ZipArchiveEntry entry = Find("xl/styles.xml");
            if (entry == null) return kinds;
            Dictionary<int, string> customFormats = new Dictionary<int, string>();
            using (XmlReader r = OpenXml(entry))
            {
                bool inCellXfs = false;
                while (r.Read())
                {
                    if (r.NodeType == XmlNodeType.Element)
                    {
                        int id;
                        if (r.LocalName == "numFmt")
                        {
                            if (int.TryParse(r.GetAttribute("numFmtId"), out id)) customFormats[id] = r.GetAttribute("formatCode") ?? "";
                        }
                        else if (r.LocalName == "cellXfs" && !r.IsEmptyElement) inCellXfs = true;
                        else if (r.LocalName == "xf" && inCellXfs)
                        {
                            int.TryParse(r.GetAttribute("numFmtId"), out id);
                            kinds.Add(FormatKind(id, customFormats));
                        }
                    }
                    else if (r.NodeType == XmlNodeType.EndElement && r.LocalName == "cellXfs") inCellXfs = false;
                }
            }
            return kinds;
        }

        private static int FormatKind(int id, Dictionary<int, string> customFormats)
        {
            if (id >= 14 && id <= 17) return KindDate;
            if (id == 22) return KindDateTime;
            if ((id >= 18 && id <= 21) || (id >= 45 && id <= 47)) return KindTime;
            string code;
            if (!customFormats.TryGetValue(id, out code)) return KindNone;
            // Saca literales "..", secciones [..] (color/locale), escapes \x, _x y *x
            string s = Regex.Replace(code, "\"[^\"]*\"|\\[[^\\]]*\\]|\\\\.|_.|\\*.", "").ToLowerInvariant();
            if (s.Contains("general")) return KindNone;
            bool hasDate = s.IndexOf('d') >= 0 || s.IndexOf('y') >= 0;
            bool hasTime = s.IndexOf('h') >= 0 || s.IndexOf('s') >= 0;
            if (!hasDate && !hasTime && s.IndexOf('m') >= 0) hasDate = true;
            if (hasDate && hasTime) return KindDateTime;
            if (hasDate) return KindDate;
            if (hasTime) return KindTime;
            return KindNone;
        }

        private string FormatNumber(double value, int style)
        {
            int kind = style >= 0 && style < _styleKinds.Count ? _styleKinds[style] : KindNone;
            if (kind != KindNone && value > -657435.0 && value < 2958466.0)
            {
                DateTime dt = DateTime.FromOADate(value);
                if (kind == KindDate) return dt.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture);
                if (kind == KindTime) return dt.ToString("HH:mm", CultureInfo.InvariantCulture);
                return dt.ToString("dd/MM/yyyy HH:mm", CultureInfo.InvariantCulture);
            }
            CultureInfo culture = CultureInfo.CurrentCulture;
            if (Math.Abs(value) < 1e11 && value == Math.Floor(value)) return value.ToString("0", culture);
            return value.ToString("0.#########", culture);
        }

        private Cell BuildCell(string type, int style, string v, string inlineText, string formula)
        {
            string fx = formula == null ? null : "=" + formula;
            switch (type)
            {
                case "s":
                {
                    int index;
                    if (!int.TryParse(v, NumberStyles.Integer, CultureInfo.InvariantCulture, out index)
                        || index < 0 || index >= _sharedStrings.Count) return null;
                    string s = _sharedStrings[index];
                    return new Cell(s, s, fx);
                }
                case "inlineStr":
                {
                    string s = DecodeEscapes(inlineText);
                    return new Cell(s, s, fx);
                }
                case "str":
                {
                    string s = DecodeEscapes(v);
                    return new Cell(s, s, fx);
                }
                case "b":
                {
                    bool b = v == "1" || string.Equals(v, "true", StringComparison.OrdinalIgnoreCase);
                    return new Cell(b, b ? "VERDADERO" : "FALSO", fx);
                }
                case "e":
                {
                    int code;
                    ErrorCodes.TryGetValue(v, out code);
                    return new Cell(code, v, fx);
                }
                case "d":
                {
                    DateTime dt;
                    if (!DateTime.TryParse(v, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out dt)) return null;
                    double oa = dt.ToOADate();
                    return new Cell(oa, FormatNumber(oa, style), fx);
                }
                default:
                {
                    if (v.Length == 0) return null;
                    double d;
                    if (!double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out d)) return new Cell(v, v, fx);
                    return new Cell(d, FormatNumber(d, style), fx);
                }
            }
        }

        private static void ParseReference(string reference, out int row, out int column)
        {
            row = 0;
            column = 0;
            foreach (char ch in reference)
            {
                if (ch >= 'A' && ch <= 'Z') column = column * 26 + (ch - 'A' + 1);
                else if (ch >= 'a' && ch <= 'z') column = column * 26 + (ch - 'a' + 1);
                else if (ch >= '0' && ch <= '9') row = row * 10 + (ch - '0');
            }
        }

        private Worksheet LoadSheet(int index)
        {
            ZipArchiveEntry entry = Find(_sheetPaths[index]);
            if (entry == null) throw new InvalidDataException("Falta la hoja en el archivo: " + _sheetPaths[index]);

            Dictionary<long, Cell> cells = new Dictionary<long, Cell>();
            int dimensionRows = 0;
            int minRow = int.MaxValue, maxRow = 0;

            using (XmlReader r = OpenXml(entry))
            {
                int row = 0, column = 0, style = 0, inPhonetic = 0;
                string type = null;
                bool inCell = false, inV = false, inF = false, inIs = false, inT = false;
                StringBuilder v = new StringBuilder(), inline = new StringBuilder(), formula = new StringBuilder();
                bool hasFormula = false;

                while (r.Read())
                {
                    if (r.NodeType == XmlNodeType.Element)
                    {
                        string name = r.LocalName;
                        if (!inCell)
                        {
                            if (name == "dimension")
                            {
                                string reference = r.GetAttribute("ref");
                                if (!string.IsNullOrEmpty(reference))
                                {
                                    string[] parts = reference.Split(':');
                                    int r1, c1, r2, c2;
                                    ParseReference(parts[0], out r1, out c1);
                                    ParseReference(parts[parts.Length - 1], out r2, out c2);
                                    if (r1 > 0 && r2 >= r1) dimensionRows = r2 - r1 + 1;
                                }
                            }
                            else if (name == "row")
                            {
                                int rowNumber;
                                row = int.TryParse(r.GetAttribute("r"), out rowNumber) ? rowNumber : row + 1;
                                column = 0;
                            }
                            else if (name == "c")
                            {
                                string reference = r.GetAttribute("r");
                                if (reference != null)
                                {
                                    int cr, cc;
                                    ParseReference(reference, out cr, out cc);
                                    if (cr > 0) row = cr;
                                    column = cc;
                                }
                                else column++;
                                type = r.GetAttribute("t");
                                int styleIndex;
                                style = int.TryParse(r.GetAttribute("s"), out styleIndex) ? styleIndex : 0;
                                if (row < minRow) minRow = row;
                                if (row > maxRow) maxRow = row;
                                if (!r.IsEmptyElement)
                                {
                                    inCell = true;
                                    hasFormula = false;
                                    v.Length = 0;
                                    inline.Length = 0;
                                    formula.Length = 0;
                                }
                            }
                        }
                        else
                        {
                            if (name == "v") inV = !r.IsEmptyElement;
                            else if (name == "f") { hasFormula = true; inF = !r.IsEmptyElement; }
                            else if (name == "is") inIs = !r.IsEmptyElement;
                            else if (name == "t" && inIs) inT = !r.IsEmptyElement;
                            else if (name == "rPh" && !r.IsEmptyElement) inPhonetic++;
                        }
                    }
                    else if (r.NodeType == XmlNodeType.EndElement)
                    {
                        if (!inCell) continue;
                        string name = r.LocalName;
                        if (name == "v") inV = false;
                        else if (name == "f") inF = false;
                        else if (name == "is") inIs = false;
                        else if (name == "t") inT = false;
                        else if (name == "rPh") inPhonetic--;
                        else if (name == "c")
                        {
                            inCell = false;
                            string formulaText = hasFormula ? (formula.Length > 0 ? formula.ToString() : "(compartida)") : null;
                            Cell cell = BuildCell(type, style, v.ToString(), inline.ToString(), formulaText);
                            if (cell != null) cells[CellCollection.Key(row, column)] = cell;
                        }
                    }
                    else if (inCell && IsTextNode(r.NodeType))
                    {
                        if (inV) v.Append(r.Value);
                        else if (inF) formula.Append(r.Value);
                        else if (inT && inPhonetic == 0) inline.Append(r.Value);
                    }
                }
            }

            // Excel guarda su UsedRange en <dimension>; si falta, se usa el rango de celdas presentes.
            int usedRows = dimensionRows > 0 ? dimensionRows : (maxRow > 0 ? maxRow - minRow + 1 : 1);
            Worksheet ws = new Worksheet(_sheetNames[index], cells, usedRows);
            _loaded[_sheetNames[index]] = ws;
            return ws;
        }
    }
}
'@
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        Add-Type -TypeDefinition $source -ReferencedAssemblies 'System.IO.Compression', 'System.Xml'
    } else {
        Add-Type -TypeDefinition $source
    }
}
