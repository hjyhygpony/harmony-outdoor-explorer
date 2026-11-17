// entry/src/main/ets/utils/PermissionUtil.ets
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common'; // 引入 Context 类型
import { BusinessError } from '@ohos.base'; // 引入错误类型

/**
 * 请求定位权限
 * @param context 必须传入 UIAbility 的 context
 */
export async function ensureLocationPermission(context: common.UIAbilityContext): Promise<boolean> {
  const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();

  try {
    // 建议同时申请模糊定位和精确定位 (适配 API 12+)
    const perms: Array<Permissions> = [
      'ohos.permission.APPROXIMATELY_LOCATION',
      'ohos.permission.LOCATION'
    ];

    const result = await atManager.requestPermissionsFromUser(context, perms);

    // 检查用户的授权结果
    // result.authResults 数组对应 perms 数组，0 表示授权成功，-1 表示失败
    let isGranted = true;
    result.authResults.forEach((authResult) => {
      if (authResult !== 0) {
        isGranted = false;
      }
    });

    console.info(`[PermissionUtil] request result: ${JSON.stringify(result.authResults)}`);
    return isGranted;

  } catch (error) {
    const err = error as BusinessError; // 显式类型转换
    console.error(`[PermissionUtil] permission request failed, code: ${err.code}, message: ${err.message}`);
    return false;
  }
}