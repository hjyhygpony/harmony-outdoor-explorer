// entry/src/main/ets/pages/Index.ets
import router from '@ohos.router';

interface FeatureItem {
  icon: string;
  title: string;
  desc: string;
  color: string;
  page: string;
}

@Entry
@Component
struct Index {
  private features: FeatureItem[] = [
    { icon: '🗺️', title: '导航地图', desc: '路线规划 · 实时导航', color: '#007DFF', page: 'pages/MapHome' },
    { icon: '🏕️', title: '户外活动', desc: '轨迹记录 · 标记 · 围栏', color: '#4CAF50', page: 'pages/OutdoorMainPage' },
    { icon: '👥', title: '实时群组', desc: '多人定位 · 位置共享 · SOS', color: '#FF9800', page: 'pages/GroupPage' }
  ];

  build() {
    Column() {
      // 顶部
      Column() {
        Text('户外探险')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)

        Text('安全出行，畅享自然')
          .fontSize(14)
          .fontColor('rgba(255,255,255,0.8)')
          .margin({ top: 8 })
      }
      .width('100%')
      .height(180)
      .padding({ top: 60 })
      .justifyContent(FlexAlign.Center)
      .linearGradient({
        angle: 135,
        colors: [['#007DFF', 0], ['#00C853', 1]]
      })

      // 功能卡片
      Column({ space: 16 }) {
        ForEach(this.features, (item: FeatureItem) => {
          Row() {
            Text(item.icon)
              .fontSize(36)
              .margin({ right: 16 })

            Column() {
              Text(item.title)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333')

              Text(item.desc)
                .fontSize(13)
                .fontColor('#999')
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Image($r('sys.media.ohos_ic_public_arrow_right'))
              .width(20)
              .height(20)
              .fillColor('#CCC')
          }
          .width('100%')
          .padding(20)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .shadow({ radius: 8, color: 'rgba(0,0,0,0.08)' })
          .onClick(() => {
            router.pushUrl({ url: item.page });
          })
        })
      }
      .padding({ left: 16, right: 16, top: 24 })

      Blank()

      // 底部提示
      Text('长按 SOS 按钮可发送紧急求助')
        .fontSize(12)
        .fontColor('#BBB')
        .margin({ bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
