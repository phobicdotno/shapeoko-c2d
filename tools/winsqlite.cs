using System;
using System.Runtime.InteropServices;
using System.Text;
public static class WinSqlite {
  const string DLL="winsqlite3.dll";
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern int sqlite3_close_v2(IntPtr db);
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int nByte, out IntPtr stmt, IntPtr tail);
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern int sqlite3_step(IntPtr stmt);
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern int sqlite3_finalize(IntPtr stmt);
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern int sqlite3_column_count(IntPtr stmt);
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr sqlite3_column_name(IntPtr stmt, int i);
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr sqlite3_column_text(IntPtr stmt, int i);
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern int sqlite3_column_type(IntPtr stmt, int i);
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr sqlite3_column_blob(IntPtr stmt, int i);
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern int sqlite3_column_bytes(IntPtr stmt, int i);
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr sqlite3_errmsg(IntPtr db);
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern int sqlite3_bind_blob(IntPtr stmt, int i, byte[] val, int n, IntPtr destructor);
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern int sqlite3_bind_text(IntPtr stmt, int i, byte[] val, int n, IntPtr destructor);
  [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] public static extern int sqlite3_bind_int(IntPtr stmt, int i, int val);
  public static string PtrToUtf8(IntPtr p){
    if(p==IntPtr.Zero) return null;
    int len=0; while(Marshal.ReadByte(p,len)!=0) len++;
    byte[] b=new byte[len]; Marshal.Copy(p,b,0,len);
    return Encoding.UTF8.GetString(b);
  }
  public static byte[] Utf8(string s){ return Encoding.UTF8.GetBytes(s+"\0"); }
  public static byte[] ColumnBlob(IntPtr stmt, int i){
    int n=sqlite3_column_bytes(stmt,i);
    byte[] b=new byte[n];
    IntPtr p=sqlite3_column_blob(stmt,i);
    if(n>0) Marshal.Copy(p,b,0,n);
    return b;
  }
}
